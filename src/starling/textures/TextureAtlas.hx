// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.textures;

import openfl.geom.Rectangle;
import openfl.utils.Dictionary;
import openfl.Vector;
import starling.utils.StarlingUtils;


/** A texture atlas is a collection of many smaller textures in one big image. This class
 *  is used to access textures from such an atlas.
 *  
 *  <p>Using a texture atlas for your textures solves two problems:</p>
 *  
 *  <ul>
 *    <li>Whenever you switch between textures, the batching of image objects is disrupted.</li>
 *    <li>Any Stage3D texture has to have side lengths that are powers of two. Starling hides 
 *        this limitation from you, but at the cost of additional graphics memory.</li>
 *  </ul>
 *  
 *  <p>By using a texture atlas, you avoid both texture switches and the power-of-two 
 *  limitation. All textures are within one big "super-texture", and Starling takes care that 
 *  the correct part of this texture is displayed.</p>
 *  
 *  <p>There are several ways to create a texture atlas. One is to use the atlas generator 
 *  script that is bundled with Starling's sibling, the <a href="http://www.sparrow-framework.org">
 *  Sparrow framework</a>. It was only tested in Mac OS X, though. A great multi-platform 
 *  alternative is the commercial tool <a href="http://www.texturepacker.com">
 *  Texture Packer</a>.</p>
 *  
 *  <p>Whatever tool you use, Starling expects the following file format:</p>
 * 
 *  <listing>
 * 	&lt;TextureAtlas imagePath='atlas.png'&gt;
 * 	  &lt;SubTexture name='texture_1' x='0'  y='0' width='50' height='50'/&gt;
 * 	  &lt;SubTexture name='texture_2' x='50' y='0' width='20' height='30'/&gt; 
 * 	&lt;/TextureAtlas&gt;
 *  </listing>
 *  
 *  <strong>Texture Frame</strong>
 *
 *  <p>If your images have transparent areas at their edges, you can make use of the 
 *  <code>frame</code> property of the Texture class. Trim the texture by removing the 
 *  transparent edges and specify the original texture size like this:</p>
 * 
 *  <listing>
 * 	&lt;SubTexture name='trimmed' x='0' y='0' height='10' width='10'
 * 	    frameX='-10' frameY='-10' frameWidth='30' frameHeight='30'/&gt;
 *  </listing>
 *
 *  <strong>Texture Rotation</strong>
 *
 *  <p>Some atlas generators can optionally rotate individual textures to optimize the texture
 *  distribution. This is supported via the boolean attribute "rotated". If it is set to
 *  <code>true</code> for a certain subtexture, this means that the texture on the atlas
 *  has been rotated by 90 degrees, clockwise. Starling will undo that rotation by rotating
 *  it counter-clockwise.</p>
 *
 *  <p>In this case, the positional coordinates (<code>x, y, width, height</code>)
 *  are expected to point at the subtexture as it is present on the atlas (in its rotated
 *  form), while the "frame" properties must describe the texture in its upright form.</p>
 *
 */
class TextureAtlas
{
	private var mAtlasTexture:Texture;
	private var mSubTextures:Map<String, Texture>;
	private var mSubTextureNames:Iterator<String>;
	
	/** helper objects */
	private static var sNames = new Vector<String>();
	
	public var texture(get, null):Texture;
	
	/** Create a texture atlas from a texture by parsing the regions from an Xml file. */
	public function new(texture:Texture, atlasXml:Xml=null)
	{
		mSubTextures = new Map<String, Texture>();
		mAtlasTexture = texture;
		
		if (atlasXml != null)
			parseAtlasXml(atlasXml);
	}
	
	/** Disposes the atlas texture. */
	public function dispose():Void
	{
		mAtlasTexture.dispose();
	}
	
	/** This function is called by the constructor and will parse an Xml in Starling's 
	 *  default atlas file format. Override this method to create custom parsing logic
	 *  (e.g. to support a different file format). */
	private function parseAtlasXml(atlasXml:Xml):Void
	{
		trace("FIX");
		var scale:Float = mAtlasTexture.scale;
		var region:Rectangle = new Rectangle();
		var frame:Rectangle  = new Rectangle();
		
		for (element in atlasXml.firstElement()) {
			if (element.nodeType == Xml.Element ) {
				
				var subTexture:Xml = cast element;
				var name:String        = StarlingUtils.cleanMasterString(subTexture.get("name"));
				
				var x:Float           = Std.parseFloat(subTexture.get("x")) / scale;
				var y:Float           = Std.parseFloat(subTexture.get("y")) / scale;
				var width:Float       = Std.parseFloat(subTexture.get("width"))  / scale;
				var height:Float      = Std.parseFloat(subTexture.get("height")) / scale;
				var frameX:Float      = Std.parseFloat(subTexture.get("frameX")) / scale;
				var frameY:Float      = Std.parseFloat(subTexture.get("frameY")) / scale;
				var frameWidth:Float  = Std.parseFloat(subTexture.get("frameWidth"))  / scale;
				var frameHeight:Float = Std.parseFloat(subTexture.get("frameHeight")) / scale;
				
				var rotatedStr:String = subTexture.get("rotated");
				var rotated:Bool = false;
				if (rotatedStr != null && rotatedStr.toLowerCase() == "true") rotated = true;
				
				region.setTo(x, y, width, height);
				frame.setTo(frameX, frameY, frameWidth, frameHeight);
				
				if (frameWidth > 0 && frameHeight > 0)
					addRegion(name, region, frame, rotated);
				else
					addRegion(name, region, null,  rotated);
			}
		}
	}
	
	/** Retrieves a SubTexture by name. Returns <code>null</code> if it is not found. */
	public function getTexture(name:String):Texture
	{
		return mSubTextures[name];
	}
	
	/** Returns all textures that start with a certain string, sorted alphabetically
	 *  (especially useful for "MovieClip"). */
	public function getTextures(prefix:String="", result:Array<Texture>=null):Array<Texture>
	{
		if (result == null) result = new Array<Texture>();
		
		for (name in getNames(prefix, sNames)) 
			result[result.length] = getTexture(name); // avoid 'push'

		sNames.length = 0;
		return result;
	}
	
	/** Returns all texture names that start with a certain string, sorted alphabetically. */
	public function getNames(prefix:String="", result:Array<String>=null):Array<String>
	{
		var name:String;
		if (result == null) result = new Array<String>();
		
		trace("FIX SORT");
		
		if (mSubTextureNames == null)
		{
			// optimization: store sorted list of texture names
			mSubTextureNames = mSubTextures.keys();
			
			/*for (name in mSubTextures) {
				if (Std.is(name, String)) mSubTextureNames.push(cast name);
			}*/
			
			
			//mSubTextureNames.sort(Array.CASEINSENSITIVE);
		}
		
		for (key in mSubTextureNames)
		{
			if (key.indexOf(prefix) == 0) {
				result.push(key);
			}
		}
		return result;
	}
	
	/** Returns the region rectangle associated with a specific name, or <code>null</code>
	 *  if no region with that name has been registered. */
	public function getRegion(name:String):Rectangle
	{
		var subTexture:SubTexture = cast mSubTextures[name];
		return subTexture != null ? subTexture.region : null;
	}
	
	/** Returns the frame rectangle of a specific region, or <code>null</code> if that region 
	 *  has no frame. */
	public function getFrame(name:String):Rectangle
	{
		var subTexture:SubTexture = cast mSubTextures[name];
		return subTexture != null ? subTexture.frame : null;
	}
	
	/** If true, the specified region in the atlas is rotated by 90 degrees (clockwise). The
	 *  SubTexture is thus rotated counter-clockwise to cancel out that transformation. */
	public function getRotation(name:String):Bool
	{
		var subTexture:SubTexture = cast mSubTextures[name];
		return subTexture != null ? subTexture.rotated : false;
	}

	/** Adds a named region for a SubTexture (described by rectangle with coordinates in
	 *  points) with an optional frame. */
	public function addRegion(name:String, region:Rectangle, frame:Rectangle=null,
							  rotated:Bool=false):Void
	{
		mSubTextures[name] = new SubTexture(mAtlasTexture, region, false, frame, rotated);
		mSubTextureNames = null;
	}
	
	/** Removes a region with a certain name. */
	public function removeRegion(name:String):Void
	{
		var subTexture:SubTexture = cast mSubTextures[name];
		if (subTexture != null) subTexture.dispose();
		mSubTextures.remove(name);
		mSubTextureNames = null;
	}
	
	/** The base texture that makes up the atlas. */
	private function get_texture():Texture { return mAtlasTexture; }
	
	// utility methods

	private static function parseBool(value:String):Bool
	{
		return value.toLowerCase() == "true";
	}
}