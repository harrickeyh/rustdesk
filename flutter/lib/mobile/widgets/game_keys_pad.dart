// On-screen key pad for games: a big D-pad plus a few common keys.
// Each button sends a real key down on touch and key up on release, so keys can be held
// and several can be pressed at once.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';

const double _kMargin = 12;
const double _kGap = 6;
final Color _kKeyColor = Colors.black.withOpacity(0.45);
final Color _kKeyDownColor = Colors.blue.withOpacity(0.7);
final Color _kBorderColor = Colors.white.withOpacity(0.7);

class GameKeysPad extends StatefulWidget {
  final FFI ffi;
  final VoidCallback onClose;
  const GameKeysPad({super.key, required this.ffi, required this.onClose});

  @override
  State<GameKeysPad> createState() => _GameKeysPadState();
}

class _GameKeysPadState extends State<GameKeysPad> {
  final Set<String> _held = {};
  final List<Rect> _blockedRects = [];

  InputModel get _inputModel => widget.ffi.inputModel;
  CursorModel get _cursorModel => widget.ffi.cursorModel;

  @override
  void dispose() {
    for (final name in _held.toList()) {
      _keyUp(name);
    }
    _setBlockedRects([]);
    super.dispose();
  }

  void _keyDown(String name) {
    if (!_held.add(name)) return;
    HapticFeedback.lightImpact();
    if (name == 'VK_CONTROL') _inputModel.ctrl = true;
    if (name == 'VK_MENU') _inputModel.alt = true;
    _inputModel.inputKey(name, down: true, press: false);
  }

  void _keyUp(String name) {
    if (!_held.remove(name)) return;
    if (name == 'VK_CONTROL') _inputModel.ctrl = false;
    if (name == 'VK_MENU') _inputModel.alt = false;
    _inputModel.inputKey(name, down: false, press: false);
  }

  void _setBlockedRects(List<Rect> rects) {
    for (final r in _blockedRects) {
      _cursorModel.removeBlockedRect(r);
    }
    _blockedRects
      ..clear()
      ..addAll(rects);
    for (final r in _blockedRects) {
      _cursorModel.addBlockedRect(r);
    }
  }

  Widget _key(String name, double w, double h,
      {String? label, IconData? icon, double fontSize = 14}) {
    return SizedBox(
      width: w,
      height: h,
      child: _HoldKey(
        down: _held.contains(name),
        onDown: () => setState(() => _keyDown(name)),
        onUp: () => setState(() => _keyUp(name)),
        child: icon != null
            ? Icon(icon, color: Colors.white, size: min(w, h) * 0.6)
            : Text(label ?? name,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: _kGap),
            children[i],
          ]
        ],
      );

  Widget _dpad(double u) {
    final size = 3 * u + 2 * _kGap;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Positioned(
            left: u + _kGap,
            top: 0,
            child: _key('VK_UP', u, u, icon: Icons.keyboard_arrow_up)),
        Positioned(
            left: 0,
            top: u + _kGap,
            child: _key('VK_LEFT', u, u, icon: Icons.keyboard_arrow_left)),
        Positioned(
            left: 2 * (u + _kGap),
            top: u + _kGap,
            child: _key('VK_RIGHT', u, u, icon: Icons.keyboard_arrow_right)),
        Positioned(
            left: u + _kGap,
            top: 2 * (u + _kGap),
            child: _key('VK_DOWN', u, u, icon: Icons.keyboard_arrow_down)),
      ]),
    );
  }

  Widget _rightPanel(double u) {
    final small = 0.75 * u;
    final navW = (5 * u + 4 * _kGap - 3 * _kGap) / 4;
    final smallFont = max(10.0, u * 0.24);
    Widget nav(String name, String label) =>
        _key(name, navW, small, label: label, fontSize: smallFont);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _row([
          nav('VK_ESCAPE', 'Esc'),
          nav('VK_INSERT', 'Ins'),
          nav('VK_HOME', 'Home'),
          nav('VK_PRIOR', 'PgUp'),
        ]),
        const SizedBox(height: _kGap),
        _row([
          SizedBox(
            width: navW,
            height: small,
            child: _HoldKey(
              down: false,
              onDown: () {},
              onUp: widget.onClose,
              child: Icon(Icons.close,
                  color: Colors.white, size: small * 0.55),
            ),
          ),
          nav('VK_DELETE', 'Del'),
          nav('VK_END', 'End'),
          nav('VK_NEXT', 'PgDn'),
        ]),
        const SizedBox(height: _kGap),
        _row([
          for (final c in ['x', 'c', 'v', 'f', 'b'])
            _key(c, u, u, label: c.toUpperCase(), fontSize: u * 0.34),
        ]),
        const SizedBox(height: _kGap),
        _row([
          _key('VK_CONTROL', u, u, label: 'Ctrl', fontSize: u * 0.26),
          _key('VK_MENU', u, u, label: 'Alt', fontSize: u * 0.26),
          _key('VK_SPACE', 3 * u + 2 * _kGap, u,
              label: 'Space', fontSize: u * 0.3),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // D-pad (3u) + right panel (5u) must fit side by side.
      final double u = max(
          24.0,
          min((min(w, h) / 6.5).clamp(44.0, 72.0).toDouble(),
              (w - 3 * _kMargin - 6 * _kGap) / 8));
      final dpadSize = 3 * u + 2 * _kGap;
      final rightW = 5 * u + 4 * _kGap;
      final rightH = 3.5 * u + 3 * _kGap;
      final rects = [
        Rect.fromLTWH(_kMargin, h - _kMargin - dpadSize, dpadSize, dpadSize),
        Rect.fromLTWH(
            w - _kMargin - rightW, h - _kMargin - rightH, rightW, rightH),
      ];
      if (!_sameRects(rects)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setBlockedRects(rects);
        });
      }
      return Stack(children: [
        Positioned(left: _kMargin, bottom: _kMargin, child: _dpad(u)),
        Positioned(right: _kMargin, bottom: _kMargin, child: _rightPanel(u)),
      ]);
    });
  }

  bool _sameRects(List<Rect> rects) {
    if (rects.length != _blockedRects.length) return false;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i] != _blockedRects[i]) return false;
    }
    return true;
  }
}

class _HoldKey extends StatefulWidget {
  final bool down;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final Widget child;
  const _HoldKey(
      {required this.down,
      required this.onDown,
      required this.onUp,
      required this.child});

  @override
  State<_HoldKey> createState() => _HoldKeyState();
}

class _HoldKeyState extends State<_HoldKey> {
  final Set<int> _pointers = {};

  void _onDown(PointerDownEvent e) {
    if (_pointers.isEmpty) widget.onDown();
    _pointers.add(e.pointer);
  }

  void _onUp(int pointer) {
    if (_pointers.remove(pointer) && _pointers.isEmpty) widget.onUp();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerUp: (e) => _onUp(e.pointer),
      onPointerCancel: (e) => _onUp(e.pointer),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.down ? _kKeyDownColor : _kKeyColor,
          border: Border.all(color: _kBorderColor, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: widget.child,
      ),
    );
  }
}
