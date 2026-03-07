import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// A widget that renders different layouts based on the available screen width.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileBody;
  final Widget? tabletBody;
  final Widget desktopBody;

  const ResponsiveLayout({
    super.key,
    required this.mobileBody,
    this.tabletBody,
    required this.desktopBody,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.mobile) {
          return mobileBody;
        } else if (constraints.maxWidth < Breakpoints.tablet) {
          // Fallback to mobileBody if tabletBody is not provided
          return tabletBody ?? mobileBody;
        } else {
          return desktopBody;
        }
      },
    );
  }
}
