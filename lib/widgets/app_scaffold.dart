import 'dart:ui';

import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import 'app_drawer.dart';
import 'save_bar.dart';

/// The app's soft background glows (primary top-left, secondary bottom-right) behind [child].
/// Radial gradients instead of BackdropFilter blobs: same look, no full-screen blur pass.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  static Widget _glow(Color color, double size) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(top: -100, left: -100, child: _glow(scheme.primary, 360)),
        Positioned(bottom: -60, right: -60, child: _glow(scheme.secondary, 300)),
        child,
      ],
    );
  }
}

/// Standard screen: blurred glass app bar over [AmbientBackground], optional drawer; drawer screens also get the
/// notification bell.
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// Pinned under the body (form [SaveBar]). Scaffold shows SnackBars above it, so they never cover the
  /// button. While the keyboard is open a [SaveBar] becomes a save icon in the app bar instead.
  final Widget? bottomNavigationBar;

  /// Drawer item this screen represents (`NavItem.id`); null = no drawer, the app bar shows a
  /// back button instead (forms and other sub-screens).
  final String? navId;

  /// false: [body] draws under the app bar and handles the top inset itself (scrolling glass effect).
  final bool safeArea;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.navId,
    this.safeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    // Keyboard open: a SaveBar moves into the app bar (keeps the visible area for the field, also in landscape;
    // iOS multi-line fields have no "done" key to get the bar back).
    final saveBar = bottomNavigationBar is SaveBar ? bottomNavigationBar as SaveBar : null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final saveInAppBar = saveBar != null && keyboardOpen;
    return Scaffold(
      extendBodyBehindAppBar: true,
      drawer: navId == null ? null : AppDrawer(currentId: navId!),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                ...?actions,
                if (navId != null) const NotificationBell(), // section screens (sub-screens keep their actions)
                if (saveInAppBar)
                  saveBar.loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Kaydediliyor'),
                          ),
                        )
                      : IconButton(
                          key: saveBar.buttonKey,
                          tooltip: saveBar.label,
                          icon: const Icon(Icons.save_rounded),
                          onPressed: saveBar.onPressed,
                        ),
              ],
            ),
          ),
        ),
      ),
      body: AmbientBackground(child: safeArea ? SafeArea(child: body) : body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar == null || saveInAppBar
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: bottomNavigationBar,
            ),
    );
  }
}
