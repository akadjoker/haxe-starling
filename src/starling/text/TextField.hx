// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.text;

import openfl.display.BitmapData;
import openfl.display.StageQuality;
import openfl.display3D.Context3DTextureFormat;
import openfl.errors.ArgumentError;
import openfl.errors.Error;
import openfl.filters.BitmapFilter;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.AntiAliasType;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import starling.utils.StarlingUtils;

import starling.core.RenderSupport;
import starling.core.Starling;
import starling.display.DisplayObject;
import starling.display.DisplayObjectContainer;
import starling.display.Image;
import starling.display.Quad;
import starling.display.QuadBatch;
import starling.display.Sprite;
import starling.events.Event;
import starling.textures.Texture;
import starling.utils.HAlign;
import starling.utils.RectangleUtil;
import starling.utils.VAlign;

/** A TextField displays text, either using standard true type fonts or custom bitmap fonts.
 *  
 *  <p>You can set all properties you are used to, like the font name and size, a color, the 
 *  horizontal and vertical alignment, etc. The border property is helpful during development, 
 *  because it lets you see the bounds of the TextField.</p>
 *  
 *  <p>There are two types of fonts that can be displayed:</p>
 *  
 *  <ul>
 *    <li>Standard TrueType fonts. This renders the text just like a conventional Flash
 *        TextField. It is recommended to embed the font, since you cannot be sure which fonts
 *        are available on the client system, and since this enhances rendering quality. 
 *        Simply pass the font name to the corresponding property.</li>
 *    <li>Bitmap fonts. If you need speed or fancy font effects, use a bitmap font instead. 
 *        That is a font that has its glyphs rendered to a texture atlas. To use it, first 
 *        register the font with the method <code>registerBitmapFont</code>, and then pass 
 *        the font name to the corresponding property of the text field.</li>
 *  </ul> 
 *    
 *  For bitmap fonts, we recommend one of the following tools:
 * 
 *  <ul>
 *    <li>Windows: <a href="http://www.angelcode.com/products/bmfont">Bitmap Font Generator</a>
 *        from Angel Code (free). Export the font data as an Xml file and the texture as a png
 *        with white characters on a transparent background (32 bit).</li>
 *    <li>Mac OS: <a href="http://glyphdesigner.71squared.com">Glyph Designer</a> from 
 *        71squared or <a href="http://http://www.bmglyph.com">bmGlyph</a> (both commercial). 
 *        They support Starling natively.</li>
 *  </ul>
 *
 *  <p>When using a bitmap font, the 'color' property is used to tint the font texture. This
 *  works by multiplying the RGB values of that property with those of the texture's pixel.
 *  If your font contains just a single color, export it in plain white and change the 'color'
 *  property to any value you like (it defaults to zero, which means black). If your font
 *  contains multiple colors, change the 'color' property to <code>Color.WHITE</code> to get
 *  the intended result.</p>
 *
 *  <strong>Batching of TextFields</strong>
 *  
 *  <p>Normally, TextFields will require exactly one draw call. For TrueType fonts, you cannot
 *  avoid that; bitmap fonts, however, may be batched if you enable the "batchable" property.
 *  This makes sense if you have several TextFields with short texts that are rendered one
 *  after the other (e.g. subsequent children of the same sprite), or if your bitmap font
 *  texture is in your main texture atlas.</p>
 *  
 *  <p>The recommendation is to activate "batchable" if it reduces your draw calls (use the
 *  StatsDisplay to check this) AND if the TextFields contain no more than about 10-15
 *  characters (per TextField). For longer texts, the batching would take up more CPU time
 *  than what is saved by avoiding the draw calls.</p>
 */
class TextField extends DisplayObjectContainer
{
	// the name container with the registered bitmap fonts
	private static var BITMAP_FONT_DATA_NAME:String = "starling.display.TextField.BitmapFonts";

	// the texture format that is used for TTF rendering
	private static var sDefaultTextureFormat:Context3DTextureFormat;

	private var mFontSize:Float;
	private var mColor:UInt;
	private var mText:String;
	private var mFontName:String;
	private var mHAlign:HAlign;
	private var mVAlign:VAlign;
	private var mBold:Bool;
	private var mItalic:Bool;
	private var mUnderline:Bool;
	private var mAutoScale:Bool;
	private var mAutoSize:String;
	private var mKerning:Bool;
	private var mNativeFilters:Array<BitmapFilter>;
	private var mRequiresRedraw:Bool;
	private var mIsRenderedText:Bool;
	private var mIsHtmlText:Bool;
	private var mTextBounds:Rectangle;
	private var mBatchable:Bool;
	
	private var mHitArea:Rectangle;
	private var mBorder:DisplayObjectContainer;
	
	private var mImage:Image;
	private var mQuadBatch:QuadBatch;
	
	/** Helper objects. */
	private static var sHelperMatrix:Matrix = new Matrix();
	private static var sNativeTextField:openfl.text.TextField = new openfl.text.TextField();
	
	private var isHorizontalAutoSize(get, null):Bool;
	private var isVerticalAutoSize(get, null):Bool;
	
	
	public var textBounds(get, null):Rectangle;
	
	public var text(get, set):String;
	public var fontName(get, set):String;
	public var fontSize(get, set):Float;
	public var color(get, set):UInt;
	public var hAlign(get, set):HAlign;
	public var vAlign(get, set):VAlign;
	public var border(get, set):Bool;
	public var bold(get, set):Bool;
	public var italic(get, set):Bool;
	public var underline(get, set):Bool;
	public var kerning(get, set):Bool;
	public var autoScale(get, set):Bool;
	public var autoSize(get, set):String;
	public var batchable(get, set):Bool;
	public var nativeFilters(get, set):Array<BitmapFilter>;
	public var isHtmlText(get, set):Bool;
	public static var defaultTextureFormat(get, set):Context3DTextureFormat;
	private static var bitmapFonts(get, null):Map<String, BitmapFont>;
	
	
	
	
	/** Create a new text field with the given properties. */
	public function new(width:Int, height:Int, text:String, fontName:String="Verdana",
							  fontSize:Float=12, color:UInt=0x0, bold:Bool=false)
	{
		super();
		mText = text != null ? text : "";
		mFontSize = fontSize;
		mColor = color;
		mHAlign = HAlign.CENTER;
		mVAlign = VAlign.CENTER;
		mBorder = null;
		mKerning = true;
		mBold = bold;
		mAutoSize = TextFieldAutoSize.NONE;
		mHitArea = new Rectangle(0, 0, width, height);
		this.fontName = fontName.toLowerCase();
		
		addEventListener(Event.FLATTEN, onFlatten);
	}
	
	/** Disposes the underlying texture data. */
	public override function dispose():Void
	{
		removeEventListener(Event.FLATTEN, onFlatten);
		if (mImage != null) mImage.texture.dispose();
		if (mQuadBatch != null) mQuadBatch.dispose();
		super.dispose();
	}
	
	private function onFlatten():Void
	{
		if (mRequiresRedraw) redraw();
	}
	
	/** @inheritDoc */
	public override function render(support:RenderSupport, parentAlpha:Float):Void
	{
		if (mRequiresRedraw) redraw();
		super.render(support, parentAlpha);
	}
	
	/** Forces the text field to be constructed right away. Normally, 
	 *  it will only do so lazily, i.e. before being rendered. */
	public function redraw():Void
	{
		if (mRequiresRedraw)
		{
			if (mIsRenderedText) createRenderedContents();
			else                 createComposedContents();
			
			updateBorder();
			mRequiresRedraw = false;
		}
	}
	
	// TrueType font rendering
	
	private function createRenderedContents():Void
	{
		if (mQuadBatch != null)
		{
			mQuadBatch.removeFromParent(true); 
			mQuadBatch = null; 
		}
		
		if (mTextBounds == null) 
			mTextBounds = new Rectangle();
		
		var texture:Texture;
		var scale:Float = Starling.ContentScaleFactor;
		var bitmapData:BitmapData = renderText(scale, mTextBounds);
		var format:Context3DTextureFormat = sDefaultTextureFormat;
		var maxTextureSize:Int = Texture.maxSize;
		var shrinkHelper:Float = 0;
		
		// re-render when size of rendered bitmap overflows 'maxTextureSize'
		while (bitmapData.width > maxTextureSize || bitmapData.height > maxTextureSize)
		{
			scale *= Math.min(
				(maxTextureSize - shrinkHelper) / bitmapData.width,
				(maxTextureSize - shrinkHelper) / bitmapData.height
			);
			bitmapData.dispose();
			bitmapData = renderText(scale, mTextBounds);
			shrinkHelper += 1;
		}

		mHitArea.width  = bitmapData.width  / scale;
		mHitArea.height = bitmapData.height / scale;
		
		texture = Texture.fromBitmapData(bitmapData, false, false, scale, format);
		texture.root.onRestore = function():Void
		{
			if (mTextBounds == null)
				mTextBounds = new Rectangle();

			bitmapData = renderText(scale, mTextBounds);
			texture.root.uploadBitmapData(renderText(scale, mTextBounds));
			bitmapData.dispose();
			bitmapData = null;
		};
		
		bitmapData.dispose();
		bitmapData = null;
		
		if (mImage == null) 
		{
			mImage = new Image(texture);
			mImage.touchable = false;
			addChild(mImage);
		}
		else 
		{ 
			mImage.texture.dispose();
			mImage.texture = texture; 
			mImage.readjustSize(); 
		}
	}

	/** This method is called immediately before the text is rendered. The intent of
	 *  'formatText' is to be overridden in a subclass, so that you can provide custom
	 *  formatting for the TextField. In the overridden method, call 'setFormat' (either
	 *  over a range of characters or the complete TextField) to modify the format to
	 *  your needs.
	 *  
	 *  @param textField  the flash.text.TextField object that you can format.
	 *  @param textFormat the default text format that's currently set on the text field.
	 */
	private function formatText(textField:flash.text.TextField, textFormat:TextFormat):Void {}

	private function renderText(scale:Float, resultTextBounds:Rectangle):BitmapData
	{
		var width:Float  = mHitArea.width  * scale;
		var height:Float = mHitArea.height * scale;
		var hAlign:HAlign = mHAlign;
		var vAlign:VAlign = mVAlign;
		
		if (isHorizontalAutoSize)
		{
			width = Math.POSITIVE_INFINITY;// Int.MAX_VALUE;
			hAlign = HAlign.LEFT;
		}
		if (isVerticalAutoSize)
		{
			height =  Math.POSITIVE_INFINITY;// Int.MAX_VALUE;
			vAlign = VAlign.TOP;
		}
		
		var align = TextFormatAlign.CENTER;
		if (hAlign == HAlign.LEFT) align = TextFormatAlign.LEFT;
		else if (hAlign == HAlign.RIGHT) align = TextFormatAlign.RIGHT;
		var textFormat:TextFormat = new TextFormat(mFontName, mFontSize * scale, mColor, mBold, mItalic, mUnderline, null, null, align);
		textFormat.kerning = cast mKerning;
		
		sNativeTextField.defaultTextFormat = textFormat;
		sNativeTextField.width = width;
		sNativeTextField.height = height;
		sNativeTextField.antiAliasType = AntiAliasType.ADVANCED;
		sNativeTextField.selectable = false;            
		sNativeTextField.multiline = true;            
		sNativeTextField.wordWrap = true;         
		
		if (mIsHtmlText) sNativeTextField.htmlText = mText;
		else             sNativeTextField.text     = mText;
		   
		sNativeTextField.embedFonts = true;
		sNativeTextField.filters = mNativeFilters;
		
		// we try embedded fonts first, non-embedded fonts are just a fallback
		if (sNativeTextField.textWidth == 0.0 || sNativeTextField.textHeight == 0.0)
			sNativeTextField.embedFonts = false;
		
		formatText(sNativeTextField, textFormat);
		
		if (mAutoScale)
			autoScaleNativeTextField(sNativeTextField);
		
		var textWidth:Float  = sNativeTextField.textWidth;
		var textHeight:Float = sNativeTextField.textHeight;
		#if js
			textHeight *= sNativeTextField.numLines;
		#end
		
		if (isHorizontalAutoSize)
			sNativeTextField.width = width = Math.ceil(textWidth + 5);
		if (isVerticalAutoSize)
			sNativeTextField.height = height = Math.ceil(textHeight + 4);
		
		// avoid invalid texture size
		if (width  < 1) width  = 1.0;
		if (height < 1) height = 1.0;
		
		var textOffsetX:Float = 0.0;
		if (hAlign == HAlign.LEFT)        textOffsetX = 2; // flash adds a 2 pixel offset
		else if (hAlign == HAlign.CENTER) textOffsetX = (width - textWidth) / 2.0;
		else if (hAlign == HAlign.RIGHT)  textOffsetX =  width - textWidth - 2;

		var textOffsetY:Float = 0.0;
		if (vAlign == VAlign.TOP)         textOffsetY = 2; // flash adds a 2 pixel offset
		else if (vAlign == VAlign.CENTER) textOffsetY = (height - textHeight) / 2.0;
		else if (vAlign == VAlign.BOTTOM) textOffsetY =  height - textHeight - 2;
		
		trace("height = " + height);
		trace("textHeight = " + textHeight);
		
		// if 'nativeFilters' are in use, the text field might grow beyond its bounds
		var filterOffset:Point = calculateFilterOffset(sNativeTextField, hAlign, vAlign);
		
		// finally: draw text field to bitmap data
		var bitmapData:BitmapData = new BitmapData(Std.int(width), Std.int(height), true, 0x0);
		var drawMatrix:Matrix = new Matrix(1, 0, 0, 1,
			filterOffset.x, filterOffset.y + cast(textOffsetY)-2);
		var drawWithQualityFunc:DocFunction = Reflect.hasField(bitmapData, "drawWithQuality") ? Reflect.getProperty(bitmapData, "drawWithQuality") : null;
			//"drawWithQuality" in bitmapData ? bitmapData["drawWithQuality"] : null;
		
		// Beginning with AIR 3.3, we can force a drawing quality. Since "LOW" produces
		// wrong output oftentimes, we force "MEDIUM" if possible.
		
		if (Reflect.isFunction(drawWithQualityFunc)) {
			var func:Dynamic = drawWithQualityFunc;
			Reflect.callMethod(bitmapData, func, [sNativeTextField, drawMatrix, null, null, null, false, StageQuality.MEDIUM]);
		}
		else
			bitmapData.draw(sNativeTextField, drawMatrix);
		
		sNativeTextField.text = "";
		
		// update textBounds rectangle
		resultTextBounds.setTo((textOffsetX + filterOffset.x) / scale,
							   (textOffsetY + filterOffset.y) / scale,
							   textWidth / scale, textHeight / scale);
		
		return bitmapData;
	}
	
	private function autoScaleNativeTextField(textField:flash.text.TextField):Void
	{
		var size:Float   = cast(textField.defaultTextFormat.size);
		var maxHeight:Int = Std.int (textField.height - 4);
		var maxWidth:Int  = Std.int (textField.width  - 4);
		
		while (textField.textWidth > maxWidth || textField.textHeight > maxHeight)
		{
			if (size <= 4) break;
			
			var format:TextFormat = textField.defaultTextFormat;
			format.size = size--;
			textField.defaultTextFormat = format;

			if (mIsHtmlText) textField.htmlText = mText;
			else             textField.text     = mText;
		}
	}
	
	private function calculateFilterOffset(textField:flash.text.TextField,
										   hAlign:HAlign, vAlign:VAlign):Point
	{
		var resultOffset:Point = new Point();
		var filters:Array<BitmapFilter> = cast textField.filters;
		
		if (filters != null && filters.length > 0)
		{
			var textWidth:Float  = textField.textWidth;
			var textHeight:Float = textField.textHeight;
			var bounds:Rectangle  = new Rectangle();
			
			for (filter in filters)
			{
				var blurX:Float    = Reflect.hasField(filter, "blurX") ? Reflect.getProperty(filter, "blurX") : 0;
				var blurY:Float    = Reflect.hasField(filter, "blurY") ? Reflect.getProperty(filter, "blurY") : 0;
				var angleDeg:Float = Reflect.hasField(filter, "angle") ? Reflect.getProperty(filter, "angle") : 0;
				var distance:Float = Reflect.hasField(filter, "distance") ? Reflect.getProperty(filter, "distance") : 0;
				var angle:Float = StarlingUtils.deg2rad(angleDeg);
				var marginX:Float = blurX * 1.33; // that's an empirical value
				var marginY:Float = blurY * 1.33;
				var offsetX:Float  = Math.cos(angle) * distance - marginX / 2.0;
				var offsetY:Float  = Math.sin(angle) * distance - marginY / 2.0;
				var filterBounds:Rectangle = new Rectangle(
					offsetX, offsetY, textWidth + marginX, textHeight + marginY);
				
				bounds = bounds.union(filterBounds);
			}
			
			if (hAlign == HAlign.LEFT && bounds.x < 0)
				resultOffset.x = -bounds.x;
			else if (hAlign == HAlign.RIGHT && bounds.y > 0)
				resultOffset.x = -(bounds.right - textWidth);
			
			if (vAlign == VAlign.TOP && bounds.y < 0)
				resultOffset.y = -bounds.y;
			else if (vAlign == VAlign.BOTTOM && bounds.y > 0)
				resultOffset.y = -(bounds.bottom - textHeight);
		}
		
		return resultOffset;
	}
	
	// bitmap font composition
	
	private function createComposedContents():Void
	{
		trace("createComposedContents");
		if (mImage != null) 
		{
			mImage.removeFromParent(true); 
			mImage.texture.dispose();
			mImage = null; 
		}
		
		if (mQuadBatch == null) 
		{ 
			mQuadBatch = new QuadBatch(); 
			mQuadBatch.touchable = false;
			addChild(mQuadBatch); 
		}
		else
			mQuadBatch.reset();
		
		var bitmapFont:BitmapFont = getBitmapFont(mFontName);
		if (bitmapFont == null) throw new Error("Bitmap font not registered: " + mFontName);
		
		var width:Float  = mHitArea.width;
		var height:Float = mHitArea.height;
		var hAlign:HAlign = mHAlign;
		var vAlign:VAlign = mVAlign;
		
		if (isHorizontalAutoSize)
		{
			width = Math.POSITIVE_INFINITY;// Int.MAX_VALUE;
			hAlign = HAlign.LEFT;
		}
		if (isVerticalAutoSize)
		{
			height = Math.POSITIVE_INFINITY;//Int.MAX_VALUE;
			vAlign = VAlign.TOP;
		}
		
		bitmapFont.fillQuadBatch(mQuadBatch,
			width, height, mText, mFontSize, mColor, hAlign, vAlign, mAutoScale, mKerning);
		mQuadBatch.batchable = mBatchable;
		
		if (mAutoSize != TextFieldAutoSize.NONE)
		{
			mTextBounds = mQuadBatch.getBounds(mQuadBatch, mTextBounds);
			
			if (isHorizontalAutoSize)
				mHitArea.width  = mTextBounds.x + mTextBounds.width;
			if (isVerticalAutoSize)
				mHitArea.height = mTextBounds.y + mTextBounds.height;
		}
		else
		{
			// hit area doesn't change, text bounds can be created on demand
			mTextBounds = null;
		}
	}
	
	// helpers
	
	private function updateBorder():Void
	{
		if (mBorder == null) return;
		
		var width:Float  = mHitArea.width;
		var height:Float = mHitArea.height;
		
		var topLine:Quad    = cast mBorder.getChildAt(0);
		var rightLine:Quad  = cast mBorder.getChildAt(1);
		var bottomLine:Quad = cast mBorder.getChildAt(2);
		var leftLine:Quad   = cast mBorder.getChildAt(3);
		
		topLine.width    = width; topLine.height    = 1;
		bottomLine.width = width; bottomLine.height = 1;
		leftLine.width   = 1;     leftLine.height   = height;
		rightLine.width  = 1;     rightLine.height  = height;
		rightLine.x  = width  - 1;
		bottomLine.y = height - 1;
		topLine.color = rightLine.color = bottomLine.color = leftLine.color = mColor;
	}
	
	// properties
	
	private function get_isHorizontalAutoSize():Bool
	{
		return mAutoSize == TextFieldAutoSize.HORIZONTAL || 
			   mAutoSize == TextFieldAutoSize.BOTH_DIRECTIONS;
	}
	
	private function get_isVerticalAutoSize():Bool
	{
		return mAutoSize == TextFieldAutoSize.VERTICAL || 
			   mAutoSize == TextFieldAutoSize.BOTH_DIRECTIONS;
	}
	
	/** Returns the bounds of the text within the text field. */
	private function get_textBounds():Rectangle
	{
		if (mRequiresRedraw) redraw();
		if (mTextBounds == null) mTextBounds = mQuadBatch.getBounds(mQuadBatch);
		return mTextBounds.clone();
	}
	
	/** @inheritDoc */
	public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
	{
		if (mRequiresRedraw) redraw();
		getTransformationMatrix(targetSpace, sHelperMatrix);
		return RectangleUtil.getBounds(mHitArea, sHelperMatrix, resultRect);
	}
	
	/** @inheritDoc */
	public override function hitTest(localPoint:Point, forTouch:Bool=false):DisplayObject
	{
		if (forTouch && (!visible || !touchable)) return null;
		else if (mHitArea.containsPoint(localPoint) && hitTestMask(localPoint)) return this;
		else return null;
	}

	/** @inheritDoc */
	private override function set_width(value:Float):Float
	{
		// different to ordinary display objects, changing the size of the text field should 
		// not change the scaling, but make the texture bigger/smaller, while the size 
		// of the text/font stays the same (this applies to the height, as well).
		
		mHitArea.width = value;
		mRequiresRedraw = true;
		return value;
	}
	
	/** @inheritDoc */
	private override function set_height(value:Float):Float
	{
		mHitArea.height = value;
		mRequiresRedraw = true;
		return value;
	}
	
	/** The displayed text. */
	private function get_text():String { return mText; }
	private function set_text(value:String):String
	{
		if (value == null) value = "";
		if (mText != value)
		{
			mText = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** The name of the font (true type or bitmap font). */
	private function get_fontName():String { return mFontName; }
	private function set_fontName(value:String):String
	{
		if (mFontName != value)
		{
			if (value == BitmapFont.MINI && bitmapFonts[value] == null)
				registerBitmapFont(new BitmapFont());
			
			mFontName = value;
			mRequiresRedraw = true;
			mIsRenderedText = getBitmapFont(value) == null;
		}
		return value;
	}
	
	/** The size of the font. For bitmap fonts, use <code>BitmapFont.NATIVE_SIZE</code> for 
	 *  the original size. */
	private function get_fontSize():Float { return mFontSize; }
	private function set_fontSize(value:Float):Float
	{
		if (mFontSize != value)
		{
			mFontSize = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** The color of the text. Note that bitmap fonts should be exported in plain white so
	 *  that tinting works correctly. If your bitmap font contains colors, set this property
	 *  to <code>Color.WHITE</code> to get the desired result. @default black */
	private function get_color():UInt { return mColor; }
	private function set_color(value:UInt):UInt
	{
		if (mColor != value)
		{
			mColor = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** The horizontal alignment of the text. @default center @see starling.utils.HAlign */
	private function get_hAlign():HAlign { return mHAlign; }
	private function set_hAlign(value:HAlign):HAlign
	{
		if (!Std.is(value, HAlign))
			throw new ArgumentError("Invalid horizontal align: " + value);
		
		if (mHAlign != value)
		{
			mHAlign = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** The vertical alignment of the text. @default center @see starling.utils.VAlign */
	private function get_vAlign():VAlign { return mVAlign; }
	private function set_vAlign(value:VAlign):VAlign
	{
		if (!Std.is(value, VAlign))
			throw new ArgumentError("Invalid vertical align: " + value);
		
		if (mVAlign != value)
		{
			mVAlign = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Draws a border around the edges of the text field. Useful for visual debugging. 
	 *  @default false */
	private function get_border():Bool { return mBorder != null; }
	private function set_border(value:Bool):Bool
	{
		if (value && mBorder == null)
		{                
			mBorder = new Sprite();
			addChild(mBorder);
			
			for (i in 0...4)
				mBorder.addChild(new Quad(1.0, 1.0));
			
			updateBorder();
		}
		else if (!value && mBorder != null)
		{
			mBorder.removeFromParent(true);
			mBorder = null;
		}
		return value;
	}
	
	/** Indicates whether the text is bold. @default false */
	private function get_bold():Bool { return mBold; }
	private function set_bold(value:Bool):Bool 
	{
		if (mBold != value)
		{
			mBold = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Indicates whether the text is italicized. @default false */
	private function get_italic():Bool { return mItalic; }
	private function set_italic(value:Bool):Bool
	{
		if (mItalic != value)
		{
			mItalic = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Indicates whether the text is underlined. @default false */
	private function get_underline():Bool { return mUnderline; }
	private function set_underline(value:Bool):Bool
	{
		if (mUnderline != value)
		{
			mUnderline = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Indicates whether kerning is enabled. @default true */
	private function get_kerning():Bool { return mKerning; }
	private function set_kerning(value:Bool):Bool
	{
		if (mKerning != value)
		{
			mKerning = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Indicates whether the font size is scaled down so that the complete text fits
	 *  into the text field. @default false */
	private function get_autoScale():Bool { return mAutoScale; }
	private function set_autoScale(value:Bool):Bool
	{
		if (mAutoScale != value)
		{
			mAutoScale = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Specifies the type of auto-sizing the TextField will do.
	 *  Note that any auto-sizing will make auto-scaling useless. Furthermore, it has 
	 *  implications on alignment: horizontally auto-sized text will always be left-, 
	 *  vertically auto-sized text will always be top-aligned. @default "none" */
	private function get_autoSize():String { return mAutoSize; }
	private function set_autoSize(value:String):String
	{
		if (mAutoSize != value)
		{
			mAutoSize = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** Indicates if TextField should be batched on rendering. This works only with bitmap
	 *  fonts, and it makes sense only for TextFields with no more than 10-15 characters.
	 *  Otherwise, the CPU costs will exceed any gains you get from avoiding the additional
	 *  draw call. @default false */
	private function get_batchable():Bool { return mBatchable; }
	private function set_batchable(value:Bool):Bool
	{ 
		mBatchable = value;
		if (mQuadBatch != null) mQuadBatch.batchable = value;
		return value;
	}

	/** The native Flash BitmapFilters to apply to this TextField.
	 *
	 *  <p>BEWARE: this property is ignored when using bitmap fonts!</p> */
	private function get_nativeFilters():Array<BitmapFilter> { return mNativeFilters; }
	private function set_nativeFilters(value:Array<BitmapFilter>) : Array<BitmapFilter>
	{
		mNativeFilters = value.concat([]);
		mRequiresRedraw = true;
		return value;
	}

	/** Indicates if the assigned text should be interpreted as HTML code. For a description
	 *  of the supported HTML subset, refer to the classic Flash 'TextField' documentation.
	 *  Clickable hyperlinks and external images are not supported.
	 *
	 *  <p>BEWARE: this property is ignored when using bitmap fonts!</p> */
	private function get_isHtmlText():Bool { return mIsHtmlText; }
	private function set_isHtmlText(value:Bool):Bool
	{
		if (mIsHtmlText != value)
		{
			mIsHtmlText = value;
			mRequiresRedraw = true;
		}
		return value;
	}
	
	/** The Context3D texture format that is used for rendering of all TrueType texts.
	 *  The default (<pre>Context3DTextureFormat.BGRA_PACKED</pre>) provides a good
	 *  compromise between quality and memory consumption; use <pre>BGRA</pre> for
	 *  the highest quality. */
	public static function get_defaultTextureFormat():Context3DTextureFormat
	{
		if (sDefaultTextureFormat == null) {
			/*if (Reflect.hasField(Context3DTextureFormat, "BGRA_PACKED")) {
				sDefaultTextureFormat = "bgraPacked4444";
			}
			else {*/
				sDefaultTextureFormat = Context3DTextureFormat.BGRA;// "bgra";
			//}
		}
		return sDefaultTextureFormat;	
	}
	public static function set_defaultTextureFormat(value:Context3DTextureFormat):Context3DTextureFormat
	{
		sDefaultTextureFormat = value;
		return value;
	}
	
	/** Makes a bitmap font available at any TextField in the current stage3D context.
	 *  The font is identified by its <code>name</code> (not case sensitive).
	 *  Per default, the <code>name</code> property of the bitmap font will be used, but you 
	 *  can pass a custom name, as well. @return the name of the font. */
	public static function registerBitmapFont(bitmapFont:BitmapFont, name:String=null):String
	{
		if (name == null) name = bitmapFont.name;
		bitmapFonts[name.toLowerCase()] = bitmapFont;
		return name;
	}
	
	/** Unregisters the bitmap font and, optionally, disposes it. */
	public static function unregisterBitmapFont(name:String, dispose:Bool=true):Void
	{
		name = name.toLowerCase();
		
		if (dispose && bitmapFonts[name] != null)
			bitmapFonts[name].dispose();
		
		bitmapFonts.remove(name);
	}
	
	/** Returns a registered bitmap font (or null, if the font has not been registered). 
	 *  The name is not case sensitive. */
	public static function getBitmapFont(name:String):BitmapFont
	{
		return bitmapFonts[name.toLowerCase()];
	}
	
	/** Stores the currently available bitmap fonts. Since a bitmap font will only work
	 *  in one Stage3D context, they are saved in Starling's 'contextData' property. */
	private static function get_bitmapFonts():Map<String, BitmapFont>
	{
		var fonts:Map<String, BitmapFont> = cast Starling.current.contextData[BITMAP_FONT_DATA_NAME];
		
		if (fonts == null)
		{
			fonts = new Map<String, BitmapFont>();
			Starling.current.contextData[BITMAP_FONT_DATA_NAME] = fonts;
		}
		
		return fonts;
	}
}