package com.zsmultitool.multi_tool_remote

import com.ryanheise.audioservice.AudioServiceActivity

/// Background audio needs an [AudioServiceActivity]. Health Connect required a
/// FragmentActivity and crashed launch on Android 11; Steps is gone, so this
/// stays a plain audio activity.
class MainActivity : AudioServiceActivity()
