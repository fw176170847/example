/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:math';
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hadss_uni_input/src/mouse_wheel_detector.dart';
import 'package:hadss_uni_input/src/gesture_utils.dart';
import 'package:hadss_uni_input/src/touch_finger.dart';

import '../hadss_uni_input.dart';
import 'package:vector_math/vector_math.dart' as vector;

/// 鼠标滚轮，滚动结束的判断时间，毫秒
const mouseWheelEndMilliSecond = 300;

/// 长按判断时间，毫秒
const longPressTimerMilliSecond = 500;

/// 触发轻扫的最慢速度
const swipeSpeedDpS = 100.0;

/// 触发滚动的最小距离
const panDistanceDp = 5.0;

/// 触发缩放的最小距离
const pinchDistanceDp = 5.0;

/// 触发缩放的最小距离
const angleDeg = 1.0;

class UnifiedGestureDetector extends StatefulWidget {
  /// Creates a widget that detects gestures.
  const UnifiedGestureDetector(
      {super.key,
      required this.child,
      this.pointerOptions,
      this.onPanStart,
      this.onPanUpdate,
      this.onPanEnd,
      this.onPanCancel,
      this.onPinchStart,
      this.onPinchUpdate,
      this.onPinchEnd,
      this.onPinchCancel,
      this.onSwipe,
      this.onRotateStart,
      this.onRotateUpdate,
      this.onRotateEnd,
      this.onRotateCancel,
      this.onContentMenu});

  final Widget child;

  /// 配置参数
  final PointerOptions? pointerOptions;

  /// 滚动/平移开始
  final Function(GestureEvent event)? onPanStart;

  /// 滚动/平移中
  final Function(GestureEvent event)? onPanUpdate;

  /// 滚动/平移结束
  final Function(GestureEvent event)? onPanEnd;

  /// 滚动/平移取消
  final Function(GestureEvent event)? onPanCancel;

  /// 缩放开始
  final Function(GestureEvent event)? onPinchStart;

  /// 缩放中
  final Function(GestureEvent event)? onPinchUpdate;

  /// 缩放结束
  final Function(GestureEvent event)? onPinchEnd;

  /// 缩放取消
  final Function(GestureEvent event)? onPinchCancel;

  /// 轻扫
  final Function(GestureEvent event)? onSwipe;

  /// 旋转开始
  final Function(GestureEvent event)? onRotateStart;

  /// 旋转中
  final Function(GestureEvent event)? onRotateUpdate;

  /// 旋转结束
  final Function(GestureEvent event)? onRotateEnd;

  /// 旋转取消
  final Function(GestureEvent event)? onRotateCancel;

  /// 旋转结束
  final Function(GestureEvent event)? onContentMenu;

  @override
  UnifiedGestureDetectorState createState() {
    return UnifiedGestureDetectorState();
  }
}

enum _MouseWheelState { Start, Update, Unknown }

class UnifiedGestureDetectorState extends State<UnifiedGestureDetector> {
  final List<TouchFinger> _touches = []; // 保存当前按住的手指触
  double _initialPinchDistance = 1.0;
  bool _isControlPressed = false;
  bool _isShiftPressed = false;
  int _pressedKeysLength = 0;
  GestureState _state = GestureState.Unknown;
  GestureState _panState = GestureState.Unknown;
  GestureState _pinchState = GestureState.Unknown;
  GestureState _rotateState = GestureState.Unknown;
  late PointerOptions _options;
  Timer? _longPressTimer;
  Timer? _scrollEndTimer;
  _MouseWheelState _mouseWheelState = _MouseWheelState.Unknown;
  DateTime _mouseWheelStartTime = DateTime.now();

  // 针对触控板
  Offset _startOffset = const Offset(0, 0);
  Offset _updateOffset = const Offset(0, 0);
  DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();

    _options = widget.pointerOptions ?? const PointerOptions();
  }

  @override
  void dispose() {
    if (_scrollEndTimer != null) {
      _scrollEndTimer!.cancel();
      _scrollEndTimer = null;
    }
    if (_longPressTimer != null) {
      _longPressTimer!.cancel();
      _longPressTimer = null;
    }
    onCancelHandler();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        onPointerSignal: onPointerSignal,
        onPointerPanZoomStart: onPointerPanZoomStart,
        onPointerPanZoomUpdate: onPointerPanZoomUpdate,
        onPointerPanZoomEnd: onPointerPanZoomEnd,
        child: MouseWheelDetector(
          onControlPress: (bool isPressed, int pressedKeysLength) {
            _isControlPressed = isPressed;
            _pressedKeysLength = pressedKeysLength;
          },
          onShiftPress: (bool isPressed, int pressedKeysLength) {
            _isShiftPressed = isPressed;
            _pressedKeysLength = pressedKeysLength;
          },
          child: widget.child,
        ));
  }

  /// 鼠标滚轮
  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // 用户开始/正在滚动
      if (_mouseWheelState == _MouseWheelState.Unknown) {
        _mouseWheelStartTime = DateTime.now();
        setState(() {
          _mouseWheelState = _MouseWheelState.Start;
        });
      } else {
        setState(() {
          _mouseWheelState = _MouseWheelState.Update;
        });
      }

      checkScrollEndTimer(event);

      if (_isControlPressed) {
        // 本组件所有手势，键盘不允许同时按下两个键
        if (_pressedKeysLength > 1) {
          return;
        }
        // 回调缩放
        if (widget.onPinchStart != null &&
            _mouseWheelState == _MouseWheelState.Start) {
          widget.onPinchStart!(GestureEvent(
              pinchCenterX: event.position.dx,
              pinchCenterY: event.position.dy,
              scale: event.scrollDelta.dy));
        } else if (widget.onPinchUpdate != null &&
            _mouseWheelState == _MouseWheelState.Update) {
          widget.onPinchUpdate!(GestureEvent(
              pinchCenterX: event.position.dx,
              pinchCenterY: event.position.dy,
              scale: event.scrollDelta.dy));
        }
      } else if (_isShiftPressed) {
        // 本组件所有手势，键盘不允许同时按下两个键
        // print('_isShiftPressed  $_pressedKeysLength');
        if (_pressedKeysLength > 1) {
          return;
        }
        print('_isShiftPressed  $_pressedKeysLength ${event.device}');
        // 回调左右平移
        onMousePanHandle(event, event.scrollDelta.dy, event.scrollDelta.dx, _mouseWheelStartTime);
      } else {
        // 回调上下滚动
        onMousePanHandle(event, event.scrollDelta.dx, event.scrollDelta.dy, _mouseWheelStartTime);
      }
    }
  }

  void checkScrollEndTimer(PointerScrollEvent event) {
    // 取消之前的计时器
    _scrollEndTimer?.cancel();

    // 设置新的计时器，300ms后认为滚动结束
    _scrollEndTimer =
        Timer(const Duration(milliseconds: mouseWheelEndMilliSecond), () {
      setState(() {
        _mouseWheelState = _MouseWheelState.Unknown;
        if (_isControlPressed && widget.onPinchEnd != null) {
          widget.onPinchEnd!(GestureEvent(
              pinchCenterX: event.position.dx,
              pinchCenterY: event.position.dy,
              scale: event.scrollDelta.dy));
        } else if (_isShiftPressed && widget.onPanEnd != null) {
          widget.onPanEnd!(GestureEvent(
              offsetX: event.scrollDelta.dy, offsetY: event.scrollDelta.dx));
        } else if (widget.onPanEnd != null) {
          widget.onPanEnd!(GestureEvent(
              offsetX: event.scrollDelta.dx, offsetY: event.scrollDelta.dy));
        }
      });
    });
  }

  void onMousePanHandle(
      PointerScrollEvent event, double offsetX, double offsetY, DateTime startTime) {
    double xSpeed = countSpeed(startTime, offsetX);
    double ySpeed = countSpeed(startTime, offsetY);
    final disPoint = sqrt(offsetX * offsetX + offsetY * offsetY);
    double speed = countSpeed(startTime, disPoint);
    print('$xSpeed $ySpeed  $speed');
    if (widget.onPanStart != null &&
        _mouseWheelState == _MouseWheelState.Start) {
      widget.onPanStart!(GestureEvent(offsetX: offsetX, offsetY: offsetY));
    } else if (widget.onPanUpdate != null &&
        _mouseWheelState == _MouseWheelState.Update) {
      widget.onPanUpdate!(GestureEvent(offsetX: offsetX, offsetY: offsetY));
    }
  }

  /// 手指触按压
  void onPointerDown(PointerDownEvent event) {
    // 添加手指触
    _touches
        .add(TouchFinger(event.pointer, event.localPosition, DateTime.now()));
    if (touchCount == 1) {
      _state = GestureState.PointerDown;
      startContentMenu(event);
    } else if (touchCount == 2) {
      // 按下了2个手指，就是缩放和旋转的开始
      if (_options.enablePinch && _pinchState == GestureState.Unknown) {
        _pinchState = GestureState.PinchStart;
      }
      if (_options.enableRotate && _rotateState == GestureState.Unknown) {
        _rotateState = GestureState.RotateStart;
      }
    }
  }

  /// 手指触移动
  void onPointerMove(PointerMoveEvent event) {
    final touch = _touches.firstWhere((touch) => touch.id == event.pointer);
    touch.currentOffset = event.localPosition;
    if (_state == GestureState.PointerDown) {
      touch.startOffset = touch.currentOffset;
      touch.downTime = DateTime.now();
      _state = GestureState.Unknown;
    }

    if (_panState == GestureState.Unknown) {
      _panState = GestureState.PanStart;
    }

    if (_panState == GestureState.PanStart ||
        _panState == GestureState.PanUpdate) {
      onPanHandler(touch.startOffset, touch.currentOffset, touch.downTime);
    }

    if (_pinchState == GestureState.PinchStart ||
        _pinchState == GestureState.PinchUpdate) {
      onPinchHandler(event, touch);
    }
    if (_rotateState == GestureState.RotateStart ||
        _rotateState == GestureState.RotateUpdate) {
      onRotateHandler(event);
    }
  }

  /// 手指触抬起
  void onPointerUp(PointerEvent event) {
    final touch = _touches.firstWhere((touch) => touch.id == event.pointer);
    // 处理轻扫
    onSwipeHandler(touch.startOffset, touch.currentOffset, touch.downTime);

    // 移除对应的手指触
    _touches.removeWhere((touch) => touch.id == event.pointer);

    // 处理滚动
    if (_panState == GestureState.PanStart) {
      _panState = GestureState.Unknown;
    } else if (_panState == GestureState.PanUpdate) {
      _panState = GestureState.Unknown;
      widget.onPanEnd?.call(GestureEvent());
    }
    // 处理缩放
    if (_pinchState == GestureState.PinchStart) {
      _pinchState = GestureState.Unknown;
    } else if (_pinchState == GestureState.PinchUpdate) {
      _pinchState = GestureState.Unknown;
      widget.onPinchEnd?.call(GestureEvent());
    } else if (_pinchState == GestureState.Unknown && touchCount == 2) {
      _pinchState = GestureState.PinchStart;
    }
    // 处理旋转
    if (_rotateState == GestureState.RotateStart) {
      _rotateState = GestureState.Unknown;
    } else if (_rotateState == GestureState.RotateUpdate) {
      _rotateState = GestureState.Unknown;
      widget.onRotateEnd?.call(GestureEvent());
    } else if (_rotateState == GestureState.Unknown && touchCount == 2) {
      _rotateState = GestureState.RotateStart;
    }
  }

  /// 触控板开始
  void onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _startOffset = event.delta;
    _startTime = DateTime.now();
    _panState = GestureState.PanStart;
    _pinchState = GestureState.PinchStart;
    _rotateState = GestureState.RotateStart;
  }

  /// 触控板过程
  void onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _updateOffset = event.localPan;
    onPanHandler(_updateOffset, _startOffset, _startTime);
    onTouchPadPinchHandler(event.scale);
    onTouchPadRotateHandler(event.rotation);
  }

  /// 触控板结素和
  void onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _panState = GestureState.Unknown;
    _pinchState = GestureState.Unknown;
    _rotateState = GestureState.Unknown;
    onSwipeHandler(_updateOffset, _startOffset, _startTime);
    widget.onPanEnd?.call(GestureEvent());
    widget.onPinchEnd?.call(GestureEvent());
    widget.onRotateEnd?.call(GestureEvent());
  }

  /// 计算缩放、旋转 初始的2指间距离
  void initPinchAndRotate() {
    if (touchCount < 2) return;
    _initialPinchDistance =
        (_touches[0].currentOffset - _touches[1].currentOffset).distance;
  }

  /// 处理轻扫
  void onSwipeHandler(
      Offset startOffset, Offset currentOffset, DateTime startTime) {
    if (!_options.enableSwipe) return;
    // 轻扫最小速度 100dp/s 当滑动速度的值小于等于0时，会被转化为默认值。
    final minSpeed =
        _options.speed > 0 ? _options.speed : const PointerOptions().speed;

    final dx = currentOffset.dx - startOffset.dx;
    final dy = currentOffset.dy - startOffset.dy;
    SwipeDirection nowDirection;
    if (dx.abs() > dy.abs()) {
      // 横向
      nowDirection = SwipeDirection.Horizontal;
    } else {
      // 竖向
      nowDirection = SwipeDirection.Vertical;
    }
    // 计算手势直线距离
    final disPoint = sqrt(dx * dx + dy * dy);
    final endTime = DateTime.now();
    // 计算时间差
    Duration difference = endTime.difference(startTime);
    // 获取毫秒数
    int milliseconds = difference.inMilliseconds;
    final speed = disPoint / milliseconds;
    if (speed * 1000 < minSpeed) {
      return;
    }
    double angle = vector.degrees(atan2(currentOffset.dy - startOffset.dy,
            currentOffset.dx - startOffset.dx)) %
        360;
    if (angle < -180.0) angle += 360.0;
    if (angle > 180.0) angle -= 360.0;

    doSwipe(angle, nowDirection, speed);
  }

  void doSwipe(double angle, SwipeDirection nowDirection, double speed) {
    double rotation = vector.radians(angle);
    if (_options.direction == SwipeDirection.None) {
      return;
    }
    bool isSwipe = _options.direction == SwipeDirection.All ||
        (_options.direction == SwipeDirection.Horizontal &&
            nowDirection == SwipeDirection.Horizontal) ||
        (_options.direction == SwipeDirection.Vertical &&
            nowDirection == SwipeDirection.Vertical);
    if (isSwipe) {
      widget.onSwipe?.call(GestureEvent(speed: speed * 1000, angle: rotation));
    }
  }

  /// 处理滚动/平移
  void onPanHandler(
      Offset startOffset, Offset currentOffset, DateTime startTime) {
    if (!_options.enablePan) return;
    // 当设定的值小于0时，按默认值5处理。
    final minDis = _options.distance < 0
        ? const PointerOptions().distance
        : _options.distance;
    final dx = currentOffset.dx - startOffset.dx;
    final dy = currentOffset.dy - startOffset.dy;
    PanDirection nowDirection;
    if (dx.abs() > dy.abs()) {
      // 横向
      nowDirection = PanDirection.Horizontal;
      nowDirection = dx > 0 ? PanDirection.Right : PanDirection.Left;
    } else {
      // 竖向
      nowDirection = PanDirection.Vertical;
      nowDirection = dy > 0 ? PanDirection.Down : PanDirection.Up;
    }
    // 计算手势直线距离
    final disPoint = sqrt(dx * dx + dy * dy);

    // 如果传入的 当前方向不在设置的方向内，返回，不处理
    if (!const PointerOptions()
        .hasPanDirection(_options.panDirection, nowDirection)) {
      return;
    }
    double xSpeed = countSpeed(startTime, dx);
    double ySpeed = countSpeed(startTime, dy);
    double speed = countSpeed(startTime, disPoint);
    if (disPoint >= minDis && _panState == GestureState.PanStart) {
      _panState = GestureState.PanUpdate;
      widget.onPanStart?.call(GestureEvent(
          offsetX: dx,
          offsetY: dy,
          velocityX: xSpeed,
          velocityY: ySpeed,
          velocity: speed));
    }
    if (_panState == GestureState.PanUpdate) {
      widget.onPanUpdate?.call(GestureEvent(
          offsetX: dx,
          offsetY: dy,
          velocityX: xSpeed,
          velocityY: ySpeed,
          velocity: speed));
    }
  }

  double countSpeed(DateTime startTime, double distance) {
    final endTime = DateTime.now();
    // 计算时间差
    Duration difference = endTime.difference(startTime);
    // 获取毫秒数
    int milliseconds = difference.inMilliseconds;
    if (milliseconds == 0) return 0;
    final speed = distance / milliseconds;
    return speed * 1000;
  }

  /// 处理缩放
  void onPinchHandler(PointerMoveEvent event, TouchFinger touch) {
    if (touchCount < 2) return;
    // 取值范围：[0, +∞)，当识别距离的值小于等于0时，会被转化为默认值。
    final minDis =
        _options.pinchDistance > 0 ? _options.pinchDistance : pinchDistanceDp;
    // 缩放
    final newDistance =
        (_touches[0].currentOffset - _touches[1].currentOffset).distance;
    final centerOffset =
        (_touches[0].currentOffset + _touches[1].currentOffset) / 2;
    final pinchDistance = newDistance - _initialPinchDistance;
    if (_pinchState == GestureState.PinchStart) {
      initPinchAndRotate();

      if (widget.onPinchStart != null && pinchDistance.abs() >= minDis) {
        // 双指捏合达到阈值触发缩放开始
        final centerOffset =
            (_touches[0].currentOffset + _touches[1].currentOffset) / 2;
        widget.onPinchStart!(GestureEvent(
            pinchCenterX: centerOffset.dx,
            pinchCenterY: centerOffset.dy,
            scale: 1));
        _pinchState = GestureState.PinchUpdate;
      }
    } else if (_pinchState == GestureState.PinchUpdate &&
        widget.onPinchUpdate != null) {
      // 双指继续，缩放进行中
      widget.onPinchUpdate!(GestureEvent(
          pinchCenterX: centerOffset.dx,
          pinchCenterY: centerOffset.dy,
          scale: pinchDistance));
    }
  }

  /// 处理触摸板缩放
  void onTouchPadPinchHandler(double scale) {
    // 取值范围：[0, +∞)，当识别距离的值小于等于0时，会被转化为默认值。
    const centerOffset = Offset(0, 0);
    final offsetScale = scale - 1;
    if (_pinchState == GestureState.PinchStart) {
      if (widget.onPinchStart != null && offsetScale.abs() >= 0.05) {
        // 双指捏合达到阈值触发缩放开始
        widget.onPinchStart!(GestureEvent(
            pinchCenterX: centerOffset.dx,
            pinchCenterY: centerOffset.dy,
            scale: offsetScale));
        _pinchState = GestureState.PinchUpdate;
      }
    } else if (_pinchState == GestureState.PinchUpdate &&
        widget.onPinchUpdate != null) {
      // 双指继续，缩放进行中
      widget.onPinchUpdate!(GestureEvent(
          pinchCenterX: centerOffset.dx,
          pinchCenterY: centerOffset.dy,
          scale: offsetScale));
    }
  }

  /// 处理旋转
  void onRotateHandler(PointerMoveEvent event) {
    if (touchCount < 2) return;
    var angle = angleBetweenLines(_touches[0], _touches[1]);
    var rotate = vector.radians(angle);
    // 当改变度数的值小于等于0或大于360时，会被转化为默认值。
    final minAngle = (_options.angle > 0 && _options.angle <= 360)
        ? _options.angle
        : const PointerOptions().angle;
    if (_rotateState == GestureState.RotateStart) {
      initPinchAndRotate();

      if (angle.abs() >= minAngle && widget.onRotateStart != null) {
        // 达到阈值，视为旋转开始
        widget.onRotateStart!(GestureEvent(angle: -rotate));
        _rotateState = GestureState.RotateUpdate;
      }
    } else if (_rotateState == GestureState.RotateUpdate &&
        widget.onRotateUpdate != null) {
      // 双指继续，旋转进行中
      widget.onRotateUpdate!(GestureEvent(angle: -rotate));
    }
  }

  /// 处理触控板旋转
  void onTouchPadRotateHandler(double rotate) {
    // 当改变度数的值小于等于0或大于360时，会被转化为默认值。
    final minAngle = (_options.angle > 0 && _options.angle <= 360)
        ? _options.angle
        : const PointerOptions().angle;
    final minRotate = vector.radians(minAngle).abs();
    if (_rotateState == GestureState.RotateStart) {
      if (rotate >= minRotate && widget.onRotateStart != null) {
        // 达到阈值，视为旋转开始
        widget.onRotateStart!(GestureEvent(angle: rotate));
        _rotateState = GestureState.RotateUpdate;
      }
    } else if (_rotateState == GestureState.RotateUpdate &&
        widget.onRotateUpdate != null) {
      // 双指继续，旋转进行中
      widget.onRotateUpdate!(GestureEvent(angle: rotate));
    }
  }

  bool inLongPressRange(TouchFinger touch) {
    return (touch.currentOffset - touch.startOffset).distanceSquared < 25;
  }

  // 处理上下文菜单
  void startContentMenu(PointerDownEvent event) {
    if (widget.onContentMenu != null) {
      if ((event.buttons == kPrimaryMouseButton ||
              event.buttons == kMiddleMouseButton) &&
          event.kind == PointerDeviceKind.mouse) {
        // 鼠标左键和中键，不触发菜单
        return;
      }
      if (event.buttons == kSecondaryMouseButton) {
        // 鼠标右键，直接回调上下文菜单
        _state = GestureState.ContentMenu;
        onContentMenuHandler(event);
      } else {
        // 长按触发上下文菜单
        _longPressTimer =
            Timer(const Duration(milliseconds: longPressTimerMilliSecond), () {
          if (touchCount == 1 &&
              _touches[0].id == event.pointer &&
              inLongPressRange(_touches[0])) {
            _state = GestureState.ContentMenu;
            onContentMenuHandler(event);
            cleanupTimer();
          }
        });
      }
    }
  }

  /// 处理上下文菜单
  void onContentMenuHandler(PointerDownEvent event) {
    widget.onContentMenu!(GestureEvent(localPosition: event.localPosition));
  }

  void cleanupTimer() {
    if (_longPressTimer != null) {
      _longPressTimer!.cancel();
      _longPressTimer = null;
    }
  }

  /// 页面突然关闭，处理cancel逻辑
  void onCancelHandler() {
    if ((_panState == GestureState.PanStart ||
            _panState == GestureState.PanUpdate) &&
        widget.onPanCancel != null) {
      widget.onPanCancel!.call(GestureEvent());
    } else if ((_pinchState == GestureState.PinchStart ||
            _pinchState == GestureState.PinchUpdate) &&
        widget.onPinchCancel != null) {
      widget.onPinchCancel!.call(GestureEvent());
    } else if ((_rotateState == GestureState.RotateStart ||
            _rotateState == GestureState.RotateUpdate) &&
        widget.onRotateCancel != null) {
      widget.onRotateCancel!.call(GestureEvent());
    }
  }

  bool isTrackpadSingleDown(PointerEvent event) =>
      touchCount == 1 &&
      event.kind == PointerDeviceKind.mouse &&
      event.buttons != kPrimaryMouseButton &&
      event.buttons != kMiddleMouseButton &&
      event.buttons != kSecondaryMouseButton;

  get touchCount => _touches.length;
}
