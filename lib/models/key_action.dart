import 'package:flutter/material.dart';

enum KeyTriggerType { singlePress, doublePress, triplePress, longPress }

extension KeyTriggerTypeExtension on KeyTriggerType {
  String get id {
    switch (this) {
      case KeyTriggerType.singlePress:
        return 'single_press';
      case KeyTriggerType.doublePress:
        return 'double_press';
      case KeyTriggerType.triplePress:
        return 'triple_press';
      case KeyTriggerType.longPress:
        return 'long_press';
    }
  }

  String get label {
    switch (this) {
      case KeyTriggerType.singlePress:
        return 'SINGLE PRESS';
      case KeyTriggerType.doublePress:
        return 'DOUBLE PRESS';
      case KeyTriggerType.triplePress:
        return 'TRIPLE PRESS';
      case KeyTriggerType.longPress:
        return 'LONG PRESS';
    }
  }

  String get badge {
    switch (this) {
      case KeyTriggerType.singlePress:
        return '1X';
      case KeyTriggerType.doublePress:
        return '2X';
      case KeyTriggerType.triplePress:
        return '3X';
      case KeyTriggerType.longPress:
        return 'HOLD';
    }
  }

  String get description {
    switch (this) {
      case KeyTriggerType.singlePress:
        return 'Tap the Essential Key once';
      case KeyTriggerType.doublePress:
        return 'Tap the Essential Key twice in quick succession';
      case KeyTriggerType.triplePress:
        return 'Tap the Essential Key three times rapidly';
      case KeyTriggerType.longPress:
        return 'Press and hold the Essential Key';
    }
  }
}

enum KeyActionType {
  none,
  torch,
  rotationLock,
  autoBrightness,
  ringerMode,
  dnd,
  voiceAssistant,
  lockScreen,
  wakeScreen,
  brightnessSlider,
  nightLight,
  extraDim,
  internetPanel,
  bluetoothPanel,
  volumePanel,
  powerMenu,
  setTimer,
  readAloud,
  copyText,
  pasteText,
  calculator,
}

class KeyActionInfo {
  final KeyActionType type;
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String category;

  const KeyActionInfo({
    required this.type,
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
  });
}

class KeyActions {
  static const List<KeyActionInfo> all = [
    KeyActionInfo(
      type: KeyActionType.torch,
      id: 'torch',
      title: 'Torch',
      description: 'Toggle rear Glyph lighting and flashlight',
      icon: Icons.bolt_rounded,
      category: 'Controls',
    ),
    KeyActionInfo(
      type: KeyActionType.rotationLock,
      id: 'rotation_lock',
      title: 'Rotation Lock',
      description: 'Toggle auto-rotate screen orientation',
      icon: Icons.screen_rotation_rounded,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.autoBrightness,
      id: 'auto_brightness',
      title: 'Auto Brightness',
      description: 'Toggle adaptive automatic screen brightness',
      icon: Icons.brightness_auto_rounded,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.ringerMode,
      id: 'ringer_mode',
      title: 'Ring / Vibrate / Silent',
      description: 'Cycle sound profiles between Ring, Vibrate, and Silent',
      icon: Icons.vibration_rounded,
      category: 'Controls',
    ),
    KeyActionInfo(
      type: KeyActionType.dnd,
      id: 'dnd',
      title: 'Do Not Disturb',
      description: 'Toggle Do Not Disturb notification silencing',
      icon: Icons.do_not_disturb_on_rounded,
      category: 'Controls',
    ),
    KeyActionInfo(
      type: KeyActionType.voiceAssistant,
      id: 'voice_assistant',
      title: 'Voice Assistant',
      description: 'Launch Google Voice Assistant',
      icon: Icons.mic_none_rounded,
      category: 'Shortcuts',
    ),
    KeyActionInfo(
      type: KeyActionType.lockScreen,
      id: 'lock_screen',
      title: 'Lock Screen',
      description: 'Turn off display and lock device',
      icon: Icons.lock_outline_rounded,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.wakeScreen,
      id: 'wake_screen',
      title: 'Wake Screen',
      description: 'Turn on display and wake device',
      icon: Icons.wb_sunny_outlined,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.brightnessSlider,
      id: 'brightness_slider',
      title: 'Brightness Slider',
      description: 'Display interactive brightness HUD overlay slider',
      icon: Icons.brightness_6_rounded,
      category: 'Controls',
    ),
    KeyActionInfo(
      type: KeyActionType.nightLight,
      id: 'night_light',
      title: 'Night Light',
      description: 'Toggle amber screen tint for eye comfort',
      icon: Icons.nightlight_round,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.extraDim,
      id: 'extra_dim',
      title: 'Extra Dim',
      description: 'Toggle extra screen dimming beyond minimum brightness',
      icon: Icons.dark_mode_outlined,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.internetPanel,
      id: 'internet_panel',
      title: 'Internet Panel',
      description: 'Open quick Wi-Fi and Mobile Data connectivity panel',
      icon: Icons.wifi_rounded,
      category: 'Panels',
    ),
    KeyActionInfo(
      type: KeyActionType.bluetoothPanel,
      id: 'bluetooth_panel',
      title: 'Bluetooth Panel',
      description: 'Open Bluetooth connections and paired devices panel',
      icon: Icons.bluetooth_rounded,
      category: 'Panels',
    ),
    KeyActionInfo(
      type: KeyActionType.volumePanel,
      id: 'volume_panel',
      title: 'Volume Panel',
      description: 'Display system audio and media volume sliders',
      icon: Icons.volume_up_rounded,
      category: 'Panels',
    ),
    KeyActionInfo(
      type: KeyActionType.powerMenu,
      id: 'power_menu',
      title: 'Power Menu',
      description: 'Open device restart and shutdown power menu dialog',
      icon: Icons.power_settings_new_rounded,
      category: 'System',
    ),
    KeyActionInfo(
      type: KeyActionType.setTimer,
      id: 'set_timer',
      title: 'Set Timer',
      description: 'Open clock timer or quick countdown',
      icon: Icons.timer_outlined,
      category: 'Tools',
    ),
    KeyActionInfo(
      type: KeyActionType.readAloud,
      id: 'read_aloud',
      title: 'Read Aloud Selected Text',
      description: 'Speak selected text or clipboard using Text-to-Speech',
      icon: Icons.record_voice_over_rounded,
      category: 'Tools',
    ),
    KeyActionInfo(
      type: KeyActionType.copyText,
      id: 'copy_text',
      title: 'Copy Selected Text',
      description: 'Copy highlighted text to system clipboard',
      icon: Icons.content_copy_rounded,
      category: 'Tools',
    ),
    KeyActionInfo(
      type: KeyActionType.pasteText,
      id: 'paste_text',
      title: 'Paste Text',
      description: 'Paste text from clipboard into active field',
      icon: Icons.content_paste_rounded,
      category: 'Tools',
    ),
    KeyActionInfo(
      type: KeyActionType.calculator,
      id: 'calculator',
      title: 'Calculator',
      description: 'Launch system calculator app',
      icon: Icons.calculate_outlined,
      category: 'Tools',
    ),
    KeyActionInfo(
      type: KeyActionType.none,
      id: 'none',
      title: 'None (Unassigned)',
      description: 'Do nothing when this key sequence is pressed',
      icon: Icons.block_rounded,
      category: 'System',
    ),
  ];

  static KeyActionInfo findById(String? id) {
    if (id == null || id.isEmpty) {
      return all.firstWhere((a) => a.type == KeyActionType.none);
    }
    return all.firstWhere(
      (a) => a.id == id,
      orElse: () => all.firstWhere((a) => a.type == KeyActionType.none),
    );
  }

  static KeyActionInfo findByType(KeyActionType type) {
    return all.firstWhere(
      (a) => a.type == type,
      orElse: () => all.firstWhere((a) => a.type == KeyActionType.none),
    );
  }
}
