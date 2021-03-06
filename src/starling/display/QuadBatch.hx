// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.display;

import openfl.display3D.Context3D;
import openfl.display3D.Context3DProgramType;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.Program3D;
import openfl.display3D.VertexBuffer3D;
import openfl.errors.Error;
import openfl.errors.IllegalOperationError;
import openfl.geom.Matrix;
import openfl.geom.Matrix3D;
import openfl.geom.Rectangle;
import openfl.Vector;

import starling.core.RenderSupport;
import starling.core.Starling;
import starling.errors.MissingContextError;
import starling.events.Event;
import starling.filters.FragmentFilter;
import starling.filters.FragmentFilterMode;
import starling.textures.Texture;
import starling.textures.TextureSmoothing;
import starling.utils.VertexData;


/** Optimizes rendering of a number of quads with an identical state.
 * 
 *  <p>The majority of all rendered objects in Starling are quads. In fact, all the default
 *  leaf nodes of Starling are quads (the Image and Quad classes). The rendering of those 
 *  quads can be accelerated by a big factor if all quads with an identical state are sent 
 *  to the GPU in just one call. That's what the QuadBatch class can do.</p>
 *  
 *  <p>The 'flatten' method of the Sprite class uses this class internally to optimize its 
 *  rendering performance. In most situations, it is recommended to stick with flattened
 *  sprites, because they are easier to use. Sometimes, however, it makes sense
 *  to use the QuadBatch class directly: e.g. you can add one quad multiple times to 
 *  a quad batch, whereas you can only add it once to a sprite. Furthermore, this class
 *  does not dispatch <code>ADDED</code> or <code>ADDED_TO_STAGE</code> events when a quad
 *  is added, which makes it more lightweight.</p>
 *  
 *  <p>One QuadBatch object is bound to a specific render state. The first object you add to a 
 *  batch will decide on the QuadBatch's state, that is: its texture, its settings for 
 *  smoothing and blending, and if it's tinted (colored vertices and/or transparency). 
 *  When you reset the batch, it will accept a new state on the next added quad.</p> 
 *  
 *  <p>The class extends DisplayObject, but you can use it even without adding it to the
 *  display tree. Just call the 'renderCustom' method from within another render method,
 *  and pass appropriate values for transformation matrix, alpha and blend mode.</p>
 *
 *  @see Sprite  
 */ 
class QuadBatch extends DisplayObject
{
	/** The maximum number of quads that can be displayed by one QuadBatch. */
	public static var MAX_NUM_QUADS:Int = 16383;
	
	private static var QUAD_PROGRAM_NAME:String = "QB_q";
	
	private var mNumQuads:Int;
	private var mSyncRequired:Bool;
	private var mBatchable:Bool;

	private var mTinted:Bool;
	private var mTexture:Texture;
	private var mSmoothing:String;
	
	private var mVertexBuffer:VertexBuffer3D;
	private var mIndexData:Vector<UInt>;
	private var mIndexBuffer:IndexBuffer3D;
	
	/** The raw vertex data of the quad. After modifying its contents, call
	 *  'onVertexDataChanged' to upload the changes to the vertex buffers. Don't change the
	 *  size of this object manually; instead, use the 'capacity' property of the QuadBatch. */
	private var mVertexData:VertexData;

	/** Helper objects. */
	//@:isVar
	private static var sHelperMatrix:Matrix = new Matrix();
	@:isVar
	private static var sRenderAlpha(get, set):Vector<Float>;
	//@:isVar
	private static var sProgramNameCache = new Map<Int, String>();
	
	public var numQuads(get, null):Int;
	public var tinted(get, null):Bool;
	public var texture(get, null):Texture;
	public var smoothing(get, null):String;
	public var premultipliedAlpha(get, null):Bool;
	public var batchable(get, set):Bool;
	public var capacity(get, set):Int;
	
	/** Creates a new QuadBatch instance with empty batch data. */
	public function new()
	{
		super();
		mVertexData = new VertexData(0, true);
		mIndexData = new Array<UInt>();
		mIndexData.fixed = false;
		
		mNumQuads = 0;
		mTinted = false;
		mSyncRequired = false;
		mBatchable = false;
		
		// Handle lost context. We use the conventional event here (not the one from Starling)
		// so we're able to create a weak event listener; this avoids memory leaks when people 
		// forget to call "dispose" on the QuadBatch.
		Starling.current.stage3D.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated, false, 0, true);
	}
	
	/** Disposes vertex- and index-buffer. */
	public override function dispose():Void
	{
		Starling.current.stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
		destroyBuffers();
		
		mVertexData.numVertices = 0;
		mIndexData.length = 0;
		mNumQuads = 0;
		
		super.dispose();
	}
	
	private function onContextCreated(event:Dynamic):Void
	{
		createBuffers();
	}
	
	/** Call this method after manually changing the contents of 'mVertexData'. */
	private function onVertexDataChanged():Void
	{
		mSyncRequired = true;
	}
	
	/** Creates a duplicate of the QuadBatch object. */
	public function clone():QuadBatch
	{
		var clone:QuadBatch = new QuadBatch();
		clone.mVertexData = mVertexData.clone(0, mNumQuads * 4);
		clone.mIndexData = mIndexData.slice(0, mNumQuads * 6);
		clone.mNumQuads = mNumQuads;
		clone.mTinted = mTinted;
		clone.mTexture = mTexture;
		clone.mSmoothing = mSmoothing;
		clone.mSyncRequired = true;
		clone.blendMode = blendMode;
		clone.alpha = alpha;
		return clone;
	}
	
	private function expand():Void
	{
		var oldCapacity:Int = this.capacity;

		if (oldCapacity >= MAX_NUM_QUADS)
			throw new Error("Exceeded maximum number of quads!");

		this.capacity = oldCapacity < 8 ? 16 : oldCapacity * 2;
	}
	
	private function createBuffers():Void
	{
		destroyBuffers();

		var numVertices:Int = mVertexData.numVertices;
		var numIndices:Int = mIndexData.length;
		var context:Context3D = Starling.Context;

		if (numVertices == 0) return;
		if (context == null)  throw new MissingContextError();
		
		mVertexBuffer = context.createVertexBuffer(numVertices, VertexData.ELEMENTS_PER_VERTEX);
		mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, numVertices);
		
		mIndexBuffer = context.createIndexBuffer(numIndices);
		mIndexBuffer.uploadFromVector(mIndexData, 0, numIndices);
		
		mSyncRequired = false;
	}
	
	private function destroyBuffers():Void
	{
		if (mVertexBuffer != null)
		{
			mVertexBuffer.dispose();
			mVertexBuffer = null;
		}

		if (mIndexBuffer != null)
		{
			mIndexBuffer.dispose();
			mIndexBuffer = null;
		}
	}

	/** Uploads the raw data of all batched quads to the vertex buffer. */
	private function syncBuffers():Void
	{
		if (mVertexBuffer == null)
		{
			createBuffers();
		}
		else
		{
			// as last parameter, we could also use 'mNumQuads * 4', but on some
			// GPU hardware (iOS!), this is slower than updating the complete buffer.
			mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, mVertexData.numVertices);
			mSyncRequired = false;
		}
	}
	
	/** Renders the current batch with custom settings for model-view-projection matrix, alpha 
	 *  and blend mode. This makes it possible to render batches that are not part of the 
	 *  display list. */ 
	public function renderCustom(mvpMatrix:Matrix3D, parentAlpha:Float=1.0, blendMode:String=null):Void
	{
		if (mNumQuads == 0) return;
		if (mSyncRequired) syncBuffers();
		
		var pma:Bool = mVertexData.premultipliedAlpha;
		var context:Context3D = Starling.Context;
		var tinted:Bool = mTinted || (parentAlpha != 1.0);
		
		sRenderAlpha[0] = sRenderAlpha[1] = sRenderAlpha[2] = pma ? parentAlpha : 1.0;
		sRenderAlpha[3] = parentAlpha;
		
		RenderSupport.setBlendFactors(pma, blendMode != null ? blendMode : this.blendMode);
		
		context.setProgram(getProgram(tinted));
		if (mTexture == null || tinted)
			context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, sRenderAlpha, 1);
		context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 1, mvpMatrix, true);
		context.setVertexBufferAt(0, mVertexBuffer, VertexData.POSITION_OFFSET, 
								  Context3DVertexBufferFormat.FLOAT_2); 
		
		if (mTexture == null || tinted)
			context.setVertexBufferAt(1, mVertexBuffer, VertexData.COLOR_OFFSET, 
									  Context3DVertexBufferFormat.FLOAT_4);
		
		if (mTexture != null)
		{
			context.setTextureAt(0, mTexture.base);
			context.setVertexBufferAt(2, mVertexBuffer, VertexData.TEXCOORD_OFFSET, 
									  Context3DVertexBufferFormat.FLOAT_2);
		}
		
		context.drawTriangles(mIndexBuffer, 0, mNumQuads * 2);
		
		if (mTexture != null)
		{
			context.setTextureAt(0, null);
			context.setVertexBufferAt(2, null);
		}
		
		context.setVertexBufferAt(1, null);
		context.setVertexBufferAt(0, null);
	}
	
	/** Resets the batch. The vertex- and index-buffers remain their size, so that they
	 *  can be reused quickly. */  
	public function reset():Void
	{
		mNumQuads = 0;
		mTexture = null;
		mSmoothing = null;
		mSyncRequired = true;
	}
	
	/** Adds an image to the batch. This method internally calls 'addQuad' with the correct
	 *  parameters for 'texture' and 'smoothing'. */ 
	public function addImage(image:Image, parentAlpha:Float=1.0, modelViewMatrix:Matrix=null,
							 blendMode:String=null):Void
	{
		addQuad(image, parentAlpha, image.texture, image.smoothing, modelViewMatrix, blendMode);
	}
	
	/** Adds a quad to the batch. The first quad determines the state of the batch,
	 *  i.e. the values for texture, smoothing and blendmode. When you add additional quads,  
	 *  make sure they share that state (e.g. with the 'isStateChange' method), or reset
	 *  the batch. */ 
	public function addQuad(quad:Quad, parentAlpha:Float=1.0, texture:Texture=null, 
							smoothing:String=null, modelViewMatrix:Matrix=null, 
							blendMode:String=null):Void
	{
		if (modelViewMatrix == null)
			modelViewMatrix = quad.transformationMatrix;
		
		var alpha:Float = parentAlpha * quad.alpha;
		var vertexID:Int = mNumQuads * 4;
		
		if (mNumQuads + 1 > mVertexData.numVertices / 4) expand();
		if (mNumQuads == 0) 
		{
			this.blendMode = blendMode != null ? blendMode : quad.blendMode;
			mTexture = texture;
			mTinted = texture != null ? (quad.tinted || parentAlpha != 1.0) : false;
			mSmoothing = smoothing;
			mVertexData.setPremultipliedAlpha(quad.premultipliedAlpha);
		}
		
		quad.copyVertexDataTransformedTo(mVertexData, vertexID, modelViewMatrix);
		
		if (alpha != 1.0)
			mVertexData.scaleAlpha(vertexID, alpha, 4);

		mSyncRequired = true;
		mNumQuads++;
	}

	/** Adds another QuadBatch to this batch. Just like the 'addQuad' method, you have to
	 *  make sure that you only add batches with an equal state. */
	public function addQuadBatch(quadBatch:QuadBatch, parentAlpha:Float=1.0, 
								 modelViewMatrix:Matrix=null, blendMode:String=null):Void
	{
		if (modelViewMatrix == null)
			modelViewMatrix = quadBatch.transformationMatrix;
		
		var tinted:Bool = quadBatch.mTinted || parentAlpha != 1.0;
		var alpha:Float = parentAlpha * quadBatch.alpha;
		var vertexID:Int = mNumQuads * 4;
		var numQuads:Int = quadBatch.numQuads;
		
		if (mNumQuads + numQuads > capacity) capacity = mNumQuads + numQuads;
		if (mNumQuads == 0) 
		{
			this.blendMode = blendMode != null ? blendMode : quadBatch.blendMode;
			mTexture = quadBatch.mTexture;
			mTinted = tinted;
			mSmoothing = quadBatch.mSmoothing;
			mVertexData.setPremultipliedAlpha(quadBatch.mVertexData.premultipliedAlpha, false);
		}
		
		quadBatch.mVertexData.copyTransformedTo(mVertexData, vertexID, modelViewMatrix,
												0, numQuads*4);
		
		if (alpha != 1.0)
			mVertexData.scaleAlpha(vertexID, alpha, numQuads*4);
		
		mSyncRequired = true;
		mNumQuads += numQuads;
	}
	
	/** Indicates if specific quads can be added to the batch without causing a state change. 
	 *  A state change occurs if the quad uses a different base texture, has a different 
	 *  'tinted', 'smoothing', 'repeat' or 'blendMode' setting, or if the batch is full
	 *  (one batch can contain up to 8192 quads). */
	public function isStateChange(tinted:Bool, parentAlpha:Float, texture:Texture, smoothing:String, blendMode:String, numQuads:Int=1):Bool
	{
		if (mNumQuads == 0) return false;
		else if (mNumQuads + numQuads > MAX_NUM_QUADS) return true; // maximum buffer size
		else if (mTexture == null && texture == null) 
			return this.blendMode != blendMode;
		else if (mTexture != null && texture != null)
			return mTexture.base != texture.base ||
				   mTexture.repeat != texture.repeat ||
				   mSmoothing != smoothing ||
				   mTinted != (tinted || parentAlpha != 1.0) ||
				   this.blendMode != blendMode;
		else return true;
	}
	
	// utility methods for manual vertex-modification
	
	/** Transforms the vertices of a certain quad by the given matrix. */
	public function transformQuad(quadID:Int, matrix:Matrix):Void
	{
		mVertexData.transformVertex(quadID * 4, matrix, 4);
		mSyncRequired = true;
	}
	
	/** Returns the color of one vertex of a specific quad. */
	public function getVertexColor(quadID:Int, vertexID:Int):UInt
	{
		return mVertexData.getColor(quadID * 4 + vertexID);
	}
	
	/** Updates the color of one vertex of a specific quad. */
	public function setVertexColor(quadID:Int, vertexID:Int, color:UInt):Void
	{
		mVertexData.setColor(quadID * 4 + vertexID, color);
		mSyncRequired = true;
	}
	
	/** Returns the alpha value of one vertex of a specific quad. */
	public function getVertexAlpha(quadID:Int, vertexID:Int):Float
	{
		return mVertexData.getAlpha(quadID * 4 + vertexID);
	}
	
	/** Updates the alpha value of one vertex of a specific quad. */
	public function setVertexAlpha(quadID:Int, vertexID:Int, alpha:Float):Void
	{
		mVertexData.setAlpha(quadID * 4 + vertexID, alpha);
		mSyncRequired = true;
	}
	
	/** Returns the color of the first vertex of a specific quad. */
	public function getQuadColor(quadID:Int):UInt
	{
		return mVertexData.getColor(quadID * 4);
	}
	
	/** Updates the color of a specific quad. */
	public function setQuadColor(quadID:Int, color:UInt):Void
	{
		for (i in 0...4)
			mVertexData.setColor(quadID * 4 + i, color);
		
		mSyncRequired = true;
	}
	
	/** Returns the alpha value of the first vertex of a specific quad. */
	public function getQuadAlpha(quadID:Int):Float
	{
		return mVertexData.getAlpha(quadID * 4);
	}
	
	/** Updates the alpha value of a specific quad. */
	public function setQuadAlpha(quadID:Int, alpha:Float):Void
	{
		for (i in 0...4)
			mVertexData.setAlpha(quadID * 4 + i, alpha);
		
		mSyncRequired = true;
	}

	/** Replaces a quad or image at a certain index with another one. */
	public function setQuad(quadID:Float, quad:Quad):Void
	{
		var matrix:Matrix = quad.transformationMatrix;
		var alpha:Float  = quad.alpha;
		var vertexID:Int  = Std.int(quadID * 4);

		quad.copyVertexDataTransformedTo(mVertexData, vertexID, matrix);
		if (alpha != 1.0) mVertexData.scaleAlpha(vertexID, alpha, 4);

		mSyncRequired = true;
	}

	/** Calculates the bounds of a specific quad, optionally transformed by a matrix.
	 *  If you pass a 'resultRect', the result will be stored in this rectangle
	 *  instead of creating a new object. */
	public function getQuadBounds(quadID:Int, transformationMatrix:Matrix=null,
								  resultRect:Rectangle=null):Rectangle
	{
		return mVertexData.getBounds(transformationMatrix, quadID * 4, 4, resultRect);
	}
	
	// display object methods
	
	/** @inheritDoc */
	public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
	{
		if (resultRect == null) resultRect = new Rectangle();
		
		var transformationMatrix:Matrix = targetSpace == this ?
			null : getTransformationMatrix(targetSpace, sHelperMatrix);
		
		return mVertexData.getBounds(transformationMatrix, 0, mNumQuads*4, resultRect);
	}
	
	/** @inheritDoc */
	public override function render(support:RenderSupport, parentAlpha:Float):Void
	{
		#if js
		if (mNumQuads != null)
		#else
		if (Math.isNaN(mNumQuads)) 
		#end
		{
			if (mBatchable)
				support.batchQuadBatch(this, parentAlpha);
			else
			{
				support.finishQuadBatch();
				support.raiseDrawCount();
				renderCustom(support.mvpMatrix3D, alpha * parentAlpha, support.blendMode);
			}
		}
	}
	
	// compilation (for flattened sprites)
	
	/** Analyses an object that is made up exclusively of quads (or other containers)
	 *  and creates a vector of QuadBatch objects representing it. This can be
	 *  used to render the container very efficiently. The 'flatten'-method of the Sprite 
	 *  class uses this method internally. */
	public static function compile(object:DisplayObject, 
								   quadBatches:Array<QuadBatch>):Void
	{
		compileObject(object, quadBatches, -1, new Matrix());
	}
	
	/** Naively optimizes a list of batches by merging all that have an identical state.
	 *  Naturally, this will change the z-order of some of the batches, so this method is
	 *  useful only for specific use-cases. */
	public static function optimize(quadBatches:Array<QuadBatch>):Void
	{
		var batch1:QuadBatch, batch2:QuadBatch;
		for (i in 0...quadBatches.length)
		{
			batch1 = quadBatches[i];
			//for (j in (i+1)...quadBatches.length)
			//{
				//batch2 = quadBatches[j];
				//if (!batch1.isStateChange(batch2.tinted, 1.0, batch2.texture,
										  //batch2.smoothing, batch2.blendMode))
				//{
					//batch1.addQuadBatch(batch2);
					//batch2.dispose();
					//quadBatches.splice(j, 1);
					//j--;
				//}
				//else ++j;
			//}
			trace("CHECK");
			for (k in (i+1)...quadBatches.length) 
			{
				var j = quadBatches.length - 1 - k;
				
				batch2 = quadBatches[j];
				if (!batch1.isStateChange(batch2.tinted, 1.0, batch2.texture,
										  batch2.smoothing, batch2.blendMode))
				{
					batch1.addQuadBatch(batch2);
					batch2.dispose();
					quadBatches.splice(j, 1);
				}
			}
		}
	}

	private static function compileObject(object:DisplayObject, quadBatches:Array<QuadBatch>, quadBatchID:Int,
		transformationMatrix:Matrix, alpha:Float=1.0, blendMode:String=null, ignoreCurrentFilter:Bool=false):Int
	{
		if (Std.is(object, Sprite3D))
			throw new IllegalOperationError("Sprite3D objects cannot be flattened");

		var i:Int;
		var quadBatch:QuadBatch;
		var isRootObject:Bool = false;
		var objectAlpha:Float = object.alpha;
		
		var container:DisplayObjectContainer = cast object;
		var quad:Quad = cast object;
		var batch:QuadBatch = cast object;
		var filter:FragmentFilter = object.filter;

		if (quadBatchID == -1)
		{
			isRootObject = true;
			quadBatchID = 0;
			objectAlpha = 1.0;
			blendMode = object.blendMode;
			ignoreCurrentFilter = true;
			if (quadBatches.length == 0) quadBatches.push(new QuadBatch());
			else quadBatches[0].reset();
		}
		else
		{
			if (object.mask != null)
				trace("[Starling] Masks are ignored on children of a flattened sprite.");
				
			if ((Std.is(object, Sprite)) && (cast(object, Sprite)).clipRect != null)
				trace("[Starling] ClipRects are ignored on children of a flattened sprite.");
		}
		
		if (filter != null && ignoreCurrentFilter)
		{
			if (filter.mode == FragmentFilterMode.ABOVE)
			{
				quadBatchID = compileObject(object, quadBatches, quadBatchID,
											transformationMatrix, alpha, blendMode, true);
			}
			
			quadBatchID = compileObject(filter.compile(object), quadBatches, quadBatchID,
										transformationMatrix, alpha, blendMode);
			
			if (filter.mode == FragmentFilterMode.BELOW)
			{
				quadBatchID = compileObject(object, quadBatches, quadBatchID,
					transformationMatrix, alpha, blendMode, true);
			}
		}
		else if (container != null)
		{
			var numChildren:Int = container.numChildren;
			var childMatrix:Matrix = new Matrix();
			
			for (i in 0...numChildren)
			{
				var child:DisplayObject = container.getChildAt(i);
				if (child.hasVisibleArea)
				{
					var childBlendMode:String = child.blendMode == BlendMode.AUTO ?
												blendMode : child.blendMode;
					childMatrix.copyFrom(transformationMatrix);
					RenderSupport.transformMatrixForObject(childMatrix, child);
					quadBatchID = compileObject(child, quadBatches, quadBatchID, childMatrix, 
												alpha*objectAlpha, childBlendMode);
				}
			}
		}
		else if (quad != null || batch != null)
		{
			var texture:Texture;
			var smoothing:String;
			var tinted:Bool;
			var numQuads:Int;
			
			if (quad != null)
			{
				var image:Image = cast quad;
				texture = image != null ? image.texture : null;
				smoothing = image != null ? image.smoothing : null;
				tinted = quad.tinted;
				numQuads = 1;
			}
			else
			{
				texture = batch.mTexture;
				smoothing = batch.mSmoothing;
				tinted = batch.mTinted;
				numQuads = batch.mNumQuads;
			}
			
			quadBatch = quadBatches[quadBatchID];
			
			if (quadBatch.isStateChange(tinted, alpha*objectAlpha, texture, 
										smoothing, blendMode, numQuads))
			{
				quadBatchID++;
				if (quadBatches.length <= quadBatchID) quadBatches.push(new QuadBatch());
				quadBatch = quadBatches[quadBatchID];
				quadBatch.reset();
			}
			
			if (quad != null)
				quadBatch.addQuad(quad, alpha, texture, smoothing, transformationMatrix, blendMode);
			else
				quadBatch.addQuadBatch(batch, alpha, transformationMatrix, blendMode);
		}
		else
		{
			throw new Error("Unsupported display object: " + Type.getClassName(Type.getClass(object)));
		}
		
		if (isRootObject)
		{
			// remove unused batches
			trace("CHECK");
			/*for (i=quadBatches.length-1; i>quadBatchID; --i) {
				quadBatches.pop().dispose();
			}*/
			for (j in (quadBatchID+1)...quadBatches.length) 
			{
				var i = quadBatches.length - j - 1;
				quadBatches.pop().dispose();
			}
		}
		
		return quadBatchID;
	}
	
	// properties
	
	/** Returns the number of quads that have been added to the batch. */
	private function get_numQuads():Int { return mNumQuads; }
	
	/** Indicates if any vertices have a non-white color or are not fully opaque. */
	private function get_tinted():Bool { return mTinted; }
	
	/** The texture that is used for rendering, or null for pure quads. Note that this is the
	 *  texture instance of the first added quad; subsequently added quads may use a different
	 *  instance, as long as the base texture is the same. */ 
	private function get_texture():Texture { return mTexture; }
	
	/** The TextureSmoothing used for rendering. */
	private function get_smoothing():String { return mSmoothing; }
	
	/** Indicates if the rgb values are stored premultiplied with the alpha value. */
	private function get_premultipliedAlpha():Bool { return mVertexData.premultipliedAlpha; }
	
	/** Indicates if the batch itself should be batched on rendering. This makes sense only
	 *  if it contains only a small number of quads (we recommend no more than 16). Otherwise,
	 *  the CPU costs will exceed any gains you get from avoiding the additional draw call.
	 *  @default false */
	private function get_batchable():Bool { return mBatchable; }
	private function set_batchable(value:Bool):Bool
	{
		mBatchable = value;
		return value;
	}
	
	/** Indicates the number of quads for which space is allocated (vertex- and index-buffers).
	 *  If you add more quads than what fits into the current capacity, the QuadBatch is
	 *  expanded automatically. However, if you know beforehand how many vertices you need,
	 *  you can manually set the right capacity with this method. */
	private function get_capacity():Int { return Std.int(mVertexData.numVertices / 4); }
	private function set_capacity(value:Int):Int
	{
		var oldCapacity:Int = capacity;
		
		if (value == oldCapacity) return value;
		else if (value == 0) throw new Error("Capacity must be > 0");
		else if (value > MAX_NUM_QUADS) value = MAX_NUM_QUADS;
		if (mNumQuads > value) mNumQuads = value;
		
		mVertexData.numVertices = value * 4;
		
		mIndexData.length = value * 6;
		
		for (i in oldCapacity...value)
		{
			mIndexData[Std.int(i*6  )] = i*4;
			mIndexData[Std.int(i*6+1)] = i*4 + 1;
			mIndexData[Std.int(i*6+2)] = i*4 + 2;
			mIndexData[Std.int(i*6+3)] = i*4 + 1;
			mIndexData[Std.int(i*6+4)] = i*4 + 3;
			mIndexData[Std.int(i*6+5)] = i*4 + 2;
		}
		
		destroyBuffers();
		mSyncRequired = true;
		return value;
	}
	
	static function get_sRenderAlpha():Vector<Float> 
	{
		if (sRenderAlpha == null) {
			sRenderAlpha = new Vector<Float>();
			sRenderAlpha.push(1);
			sRenderAlpha.push(1);
			sRenderAlpha.push(1);
			sRenderAlpha.push(1);
		}
		return sRenderAlpha;
	}
	
	static function set_sRenderAlpha(value:Vector<Float>):Vector<Float> 
	{
		return sRenderAlpha = value;
	}

	// program management
	
	private function getProgram(tinted:Bool):Program3D
	{
		var target:Starling = Starling.current;
		var programName:String = QUAD_PROGRAM_NAME;
		
		if (mTexture != null) {
			programName = getImageProgramName(tinted, mTexture.mipMapping, mTexture.repeat, mTexture.format, mSmoothing);
		}
		
		var program:Program3D = target.getProgram(programName);
		
		if (program == null)
		{
			// this is the input data we'll pass to the shaders:
			// 
			// va0 -> position
			// va1 -> color
			// va2 -> texCoords
			// vc0 -> alpha
			// vc1 -> mvpMatrix
			// fs0 -> texture
			
			var vertexShader:String;
			var fragmentShader:String;

			if (mTexture == null) // Quad-Shaders
			{
				vertexShader =
					"m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mul v0, va1, vc0 \n";  // multiply alpha (vc0) with color (va1)
				
				fragmentShader =
					"mov oc, v0       \n";  // output color
			}
			else // Image-Shaders
			{
				vertexShader = tinted ?
					"m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mul v0, va1, vc0 \n" + // multiply alpha (vc0) with color (va1)
					"mov v1, va2      \n"   // pass texture coordinates to fragment program
					:
					"m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mov v1, va2      \n";  // pass texture coordinates to fragment program
				
				fragmentShader = tinted ?
					"tex ft1,  v1, fs0 <???> \n" + // sample texture 0
					"mul  oc, ft1,  v0       \n"   // multiply color with texel color
					:
					"tex  oc,  v1, fs0 <???> \n";  // sample texture 0
				
				fragmentShader = StringTools.replace(fragmentShader, "<???>",
					RenderSupport.getTextureLookupFlags(
						mTexture.format, mTexture.mipMapping, mTexture.repeat, smoothing));
					
				/*fragmentShader = fragmentShader.replace("<???>",
					RenderSupport.getTextureLookupFlags(
						mTexture.format, mTexture.mipMapping, mTexture.repeat, smoothing));*/
			}
			
			program = target.registerProgramFromSource(programName,
				vertexShader, fragmentShader);
		}
		
		return program;
	}
	
	private static function getImageProgramName(tinted:Bool, mipMap:Bool=true, 
												repeat:Bool=false, format:Context3DTextureFormat=null,
												smoothing:String="bilinear"):String
	{
		if (format == null) format = Context3DTextureFormat.BGRA;
		var bitField:UInt = 0;
		
		if (tinted) bitField |= 1;
		if (mipMap) bitField |= 1 << 1;
		if (repeat) bitField |= 1 << 2;
		
		if (smoothing == TextureSmoothing.NONE)
			bitField |= 1 << 3;
		else if (smoothing == TextureSmoothing.TRILINEAR)
			bitField |= 1 << 4;
		
		if (format == Context3DTextureFormat.COMPRESSED)
			bitField |= 1 << 5;
		else if (format == Context3DTextureFormat.COMPRESSED_ALPHA)
			bitField |= 1 << 6;
		
		var name:String = sProgramNameCache[bitField];
		
		if (name == null)
		{
			name = "QB_i." + StringTools.hex(bitField);
			sProgramNameCache[bitField] = name;
		}
		
		return name;
	}
}