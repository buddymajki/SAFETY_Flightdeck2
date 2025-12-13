import 'package:flutter/material.dart';

/// Responsive layout utilities for the app
/// Provides helper methods and widgets for responsive design
class ResponsiveLayout {
  // Breakpoints for responsive design
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 900;
  static const double desktopMaxWidth = 900; // Max content width on desktop 1200 volt, de leszedtem
  static const double desktopHorizontalPadding = 32;
  static const double mobileHorizontalPadding = 16;

  /// Determines if the current screen size is mobile
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileMaxWidth;
  }

  /// Determines if the current screen size is tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileMaxWidth && width < tabletMaxWidth;
  }

  /// Determines if the current screen size is desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletMaxWidth;
  }

  /// Get responsive padding based on screen size
  static EdgeInsets getResponsivePadding(BuildContext context) {
    if (isDesktop(context)) {
      return const EdgeInsets.all(desktopHorizontalPadding);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(24);
    } else {
      return const EdgeInsets.all(mobileHorizontalPadding);
    }
  }

  /// Get responsive horizontal padding
  static double getResponsiveHorizontalPadding(BuildContext context) {
    if (isDesktop(context)) {
      return desktopHorizontalPadding;
    } else if (isTablet(context)) {
      return 24;
    } else {
      return mobileHorizontalPadding;
    }
  }

  /// Get the maximum width for content on larger screens
  static double getMaxContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= desktopMaxWidth) {
      return screenWidth;
    }
    return desktopMaxWidth;
  }
}

/// A wrapper widget that constrains content to a maximum width on large screens
/// and centers it horizontally. Useful for preventing content from stretching
/// too wide on desktop monitors.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  final Alignment alignment;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final contentMaxWidth = maxWidth ?? ResponsiveLayout.desktopMaxWidth;
    final isDesktop = ResponsiveLayout.isDesktop(context);
    
    if (!isDesktop) {
      // On mobile/tablet, use the child directly with responsive padding
      return Padding(
        padding: padding ?? ResponsiveLayout.getResponsivePadding(context),
        child: child,
      );
    }

    // On desktop, center the content and constrain its width
    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        padding: padding ?? ResponsiveLayout.getResponsivePadding(context),
        child: child,
      ),
    );
  }
}

/// A responsive list view that handles both mobile and desktop layouts
class ResponsiveListView extends StatelessWidget {
  final List<Widget> children;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final double? maxWidth;

  const ResponsiveListView({
    super.key,
    required this.children,
    this.physics,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final contentMaxWidth = maxWidth ?? ResponsiveLayout.desktopMaxWidth;
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final responsivePadding = padding ?? ResponsiveLayout.getResponsivePadding(context);

    if (!isDesktop) {
      return ListView(
        physics: physics,
        padding: responsivePadding,
        children: children,
      );
    }

    // On desktop, center content and apply max width
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        child: ListView(
          physics: physics,
          padding: responsivePadding,
          children: children,
        ),
      ),
    );
  }
}

/// A responsive form wrapper that ensures form fields don't get too wide
class ResponsiveForm extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  final double? maxWidth;

  const ResponsiveForm({
    super.key,
    required this.children,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      maxWidth: maxWidth,
      padding: padding,
      child: Form(
        child: Column(
          children: children,
        ),
      ),
    );
  }
}
