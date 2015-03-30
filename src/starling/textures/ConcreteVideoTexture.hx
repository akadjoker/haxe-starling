// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2015 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.textures;

import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.TextureBase;
import openfl.errors.ArgumentError;

/** A concrete texture that may only be used for a 'VideoTexture' base.
 *  For internal use only. */
/*internal*/
class ConcreteVideoTexture extends ConcreteTexture
{
	/** Creates a new VideoTexture. 'base' must be of type 'VideoTexture'. */
	public function ConcreteVideoTexture(base:TextureBase, scale:Float = 1)
	{
		// we must not reference the "VideoTexture" class directly
		// because it's only available in AIR.

		var format:String = Context3DTextureFormat.BGRA;
		var width:Float  = "videoWidth"  in base ? base["videoWidth"]  : 0;
		var height:Float = "videoHeight" in base ? base["videoHeight"] : 0;

		super(base, format, width, height, false, false, false, scale, false);

		if (Type.getClassName(base) != "flash.display3D.textures::VideoTexture")
			throw new ArgumentError("'base' must be VideoTexture");
	}

	/** The actual width of the video in pixels. */
	override public function get_nativeWidth():Float
	{
		return base["videoWidth"];
	}

	/** The actual height of the video in pixels. */
	override public function get_nativeHeight():Float
	{
		return base["videoHeight"];
	}

	/** inheritDoc */
	override public function get_width():Float
	{
		return nativeWidth / scale;
	}

	/** inheritDoc */
	override public function get_height():Float
	{
		return nativeHeight / scale;
	}
}