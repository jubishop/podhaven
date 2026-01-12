// Copyright Justin Bishop, 2025

import SwiftUI
import UIKit

/*
 Guidance:

 - Mirror text styles:
   ```
   @BoundedScaledMetric(
     relativeTo: .body
   ) var iconSize
   ```
   Keeps icons aligned with a view’s `.body` text without hand-tuning points.

 - Nudge relative sizes:
   ```
   @BoundedScaledMetric(
     wrappedDelta: 2,
     relativeTo: .body
   ) var pillHeight
   ```
   Bumps a control slightly larger than the current body type.

 - Clamp dynamic type:
   ```
   @BoundedScaledMetric(
     relativeTo: .caption,
     categories: .accessibility1 ... .accessibility3
   ) var compactCaptionMetric
   ```
   Limits scaling to specific Dynamic Type categories.

 - Shrink specific categories:
   ```
   @BoundedScaledMetric(
     wrappedDelta: -1,
     relativeTo: .subheadline,
     categories: ..<.extraExtraExtraLarge
   ) var trimmedSubheadlineMetric
   ```
   Trims values after a given Dynamic Type threshold.

 - Cap point sizes:
   ```
   @BoundedScaledMetric(
     wrappedValue: 18,
     relativeTo: .headline,
     pointSizes: 14 ... 22
   ) var boundedHeadlineMetric
   ```
   Prevents the value from shrinking or expanding beyond explicit bounds.

 - One-sided point bounds:
   ```
   @BoundedScaledMetric(
     relativeTo: .footnote,
     pointSizes: ...16
   ) var cappedFootnoteMetric
   ```
   Caps only the upper bound while allowing Dynamic Type to shrink freely.

 - Offset within point bounds:
   ```
   @BoundedScaledMetric(
     wrappedDelta: 1,
     relativeTo: .callout,
     pointSizes: 13 ... 19
   ) var offsetCalloutMetric
   ```
   Nudges the base size while respecting minimum/maximum caps.

 - Mix bounds:
   ```
   @BoundedScaledMetric(
     wrappedValue: 16,
     relativeTo: .subheadline,
     categories: ..<.accessibility2,
     pointSizes: 14 ... 20
   ) var boundedSubheadlineMetric
   ```
   Combines category and point constraints when both matter.

 - Full control with delta:
   ```
   @BoundedScaledMetric(
     wrappedDelta: 3,
     relativeTo: .caption2,
     categories: .medium ...,
     pointSizes: 12 ... 18
   ) var fullyBoundedCaptionMetric
   ```
   Applies all constraints plus an offset tied to Dynamic Type.
 */

@propertyWrapper
struct BoundedScaledMetric: DynamicProperty {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private let baseValue: CGFloat
  private let metrics: UIFontMetrics
  private let categoryBounds: RangeBounds<DynamicTypeSize>?
  private let pointBounds: RangeBounds<CGFloat>?

  // MARK: Baseline Only

  init(wrappedValue baseSize: CGFloat, relativeTo textStyle: Font.TextStyle) {
    self.init(
      baseValue: baseSize,
      textStyle: UIFont.TextStyle(textStyle),
      categoryBounds: nil,
      pointBounds: nil
    )
  }

  init(wrappedDelta deltaSize: CGFloat, relativeTo textStyle: Font.TextStyle) {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize + deltaSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: nil,
      pointBounds: nil
    )
  }

  init(relativeTo textStyle: Font.TextStyle) {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: nil,
      pointBounds: nil
    )
  }

  // MARK: Category Bounds

  init<C>(
    wrappedValue baseSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C
  ) where C: RangeBoundsConvertible, C.Bound == DynamicTypeSize {
    self.init(
      baseValue: baseSize,
      textStyle: UIFont.TextStyle(textStyle),
      categoryBounds: categoryRange.bounds,
      pointBounds: nil
    )
  }

  init<C>(
    wrappedDelta deltaSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C
  ) where C: RangeBoundsConvertible, C.Bound == DynamicTypeSize {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize + deltaSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: categoryRange.bounds,
      pointBounds: nil
    )
  }

  init<C>(
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C
  ) where C: RangeBoundsConvertible, C.Bound == DynamicTypeSize {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: categoryRange.bounds,
      pointBounds: nil
    )
  }

  // MARK: Point Size Bounds

  init<P>(
    wrappedValue baseSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    pointSizes pointSizeRange: P
  ) where P: RangeBoundsConvertible, P.Bound == CGFloat {
    self.init(
      baseValue: baseSize,
      textStyle: UIFont.TextStyle(textStyle),
      categoryBounds: nil,
      pointBounds: pointSizeRange.bounds
    )
  }

  init<P>(
    wrappedDelta deltaSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    pointSizes pointSizeRange: P
  ) where P: RangeBoundsConvertible, P.Bound == CGFloat {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize + deltaSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: nil,
      pointBounds: pointSizeRange.bounds
    )
  }

  init<P>(
    relativeTo textStyle: Font.TextStyle,
    pointSizes pointSizeRange: P
  ) where P: RangeBoundsConvertible, P.Bound == CGFloat {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: nil,
      pointBounds: pointSizeRange.bounds
    )
  }

  // MARK: Category + Point Size Bounds

  init<C, P>(
    wrappedValue baseSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C,
    pointSizes pointSizeRange: P
  )
  where
    C: RangeBoundsConvertible,
    C.Bound == DynamicTypeSize,
    P: RangeBoundsConvertible,
    P.Bound == CGFloat
  {
    self.init(
      baseValue: baseSize,
      textStyle: UIFont.TextStyle(textStyle),
      categoryBounds: categoryRange.bounds,
      pointBounds: pointSizeRange.bounds
    )
  }

  init<C, P>(
    wrappedDelta deltaSize: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C,
    pointSizes pointSizeRange: P
  )
  where
    C: RangeBoundsConvertible,
    C.Bound == DynamicTypeSize,
    P: RangeBoundsConvertible,
    P.Bound == CGFloat
  {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize + deltaSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: categoryRange.bounds,
      pointBounds: pointSizeRange.bounds
    )
  }

  init<C, P>(
    relativeTo textStyle: Font.TextStyle,
    categories categoryRange: C,
    pointSizes pointSizeRange: P
  )
  where
    C: RangeBoundsConvertible,
    C.Bound == DynamicTypeSize,
    P: RangeBoundsConvertible,
    P.Bound == CGFloat
  {
    let uiStyle = UIFont.TextStyle(textStyle)
    let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
    self.init(
      baseValue: baseSize,
      textStyle: uiStyle,
      categoryBounds: categoryRange.bounds,
      pointBounds: pointSizeRange.bounds
    )
  }

  // MARK: DynamicProperty

  var wrappedValue: CGFloat {
    let clampedCategory = dynamicTypeSize.clamped(
      minimum: categoryBounds?.lower,
      maximum: categoryBounds?.upper
    )

    return
      metrics.scaledValue(
        for: baseValue,
        compatibleWith: traitCollection(for: clampedCategory)
      )
      .clamped(min: pointBounds?.lower, max: pointBounds?.upper)
  }

  var projectedValue: CGFloat { wrappedValue }

  private func traitCollection(for size: DynamicTypeSize) -> UITraitCollection {
    UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
  }

  private init(
    baseValue: CGFloat,
    textStyle: UIFont.TextStyle,
    categoryBounds: RangeBounds<DynamicTypeSize>?,
    pointBounds: RangeBounds<CGFloat>?
  ) {
    if let lower = categoryBounds?.lower,
      let upper = categoryBounds?.upper
    {
      Assert.precondition(
        lower <= upper,
        "Minimum Dynamic Type size must be <= maximum."
      )
    }

    if let lower = pointBounds?.lower,
      let upper = pointBounds?.upper
    {
      Assert.precondition(
        lower <= upper,
        "Minimum point size must be <= maximum point size."
      )
    }

    self.baseValue = baseValue
    self.metrics = UIFontMetrics(forTextStyle: textStyle)
    self.categoryBounds = categoryBounds
    self.pointBounds = pointBounds
  }
}
