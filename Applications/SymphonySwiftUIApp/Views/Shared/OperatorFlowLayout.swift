import Foundation
import SwiftUI

struct OperatorFlowLayout: Layout {
  var spacing: CGFloat
  var rowSpacing: CGFloat

  init(spacing: CGFloat = 8, rowSpacing: CGFloat? = nil) {
    self.spacing = spacing
    self.rowSpacing = rowSpacing ?? spacing
  }

  struct Cache {
    var sizes: [CGSize]
  }

  func makeCache(subviews: Subviews) -> Cache {
    var sizes = [CGSize]()
    sizes.reserveCapacity(subviews.count)
    for subview in subviews {
      sizes.append(subview.sizeThatFits(.unspecified))
    }
    return Cache(sizes: sizes)
  }

  func updateCache(_ cache: inout Cache, subviews: Subviews) {
    var sizes = [CGSize]()
    sizes.reserveCapacity(subviews.count)
    for subview in subviews {
      sizes.append(subview.sizeThatFits(.unspecified))
    }
    cache.sizes = sizes
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) -> CGSize {
    let maxWidth = operatorFlowLayoutMaxWidth(for: proposal.width)
    let rows = makeRows(maxWidth: maxWidth, sizes: cache.sizes)
    var rowWidths = [CGFloat]()
    var rowHeights = [CGFloat]()
    rowWidths.reserveCapacity(rows.count)
    rowHeights.reserveCapacity(rows.count)
    for row in rows {
      rowWidths.append(row.width)
      rowHeights.append(row.height)
    }
    return operatorFlowLayoutMeasuredSize(
      proposedWidth: proposal.width,
      rowWidths: rowWidths,
      rowHeights: rowHeights,
      rowSpacing: rowSpacing
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) {
    let rows = makeRows(maxWidth: bounds.width, sizes: cache.sizes)
    var y = bounds.minY

    for row in rows {
      var x = bounds.minX
      for index in row.indices {
        let size = cache.sizes[index]
        subviews[index].place(
          at: CGPoint(x: x, y: y),
          proposal: ProposedViewSize(width: size.width, height: size.height)
        )
        x += size.width + spacing
      }
      y += row.height + rowSpacing
    }
  }

  private func makeRows(maxWidth: CGFloat, sizes: [CGSize]) -> [OperatorFlowLayoutRow] {
    guard sizes.isEmpty == false else {
      return []
    }

    var rows = [OperatorFlowLayoutRow]()
    var currentRow = OperatorFlowLayoutRow()

    for (index, size) in sizes.enumerated() {
      let proposedWidth =
        currentRow.indices.isEmpty ? size.width : currentRow.width + spacing + size.width
      if proposedWidth > maxWidth, currentRow.indices.isEmpty == false {
        rows.append(currentRow)
        currentRow = OperatorFlowLayoutRow()
      }

      currentRow.indices.append(index)
      currentRow.width =
        currentRow.indices.count == 1 ? size.width : currentRow.width + spacing + size.width
      currentRow.height = max(currentRow.height, size.height)
    }

    rows.append(currentRow)
    return rows
  }
}

func operatorFlowLayoutMaxWidth(for proposedWidth: CGFloat?) -> CGFloat {
  if let proposedWidth {
    return proposedWidth
  }
  return .greatestFiniteMagnitude
}

func operatorFlowLayoutMeasuredSize(
  proposedWidth: CGFloat?,
  rowWidths: [CGFloat],
  rowHeights: [CGFloat],
  rowSpacing: CGFloat
) -> CGSize {
  var width: CGFloat = 0
  for rowWidth in rowWidths {
    width = max(width, rowWidth)
  }

  var height: CGFloat = 0
  for rowHeight in rowHeights {
    height += rowHeight
  }
  height += rowSpacing * CGFloat(max(rowHeights.count - 1, 0))

  if let proposedWidth {
    return CGSize(width: proposedWidth, height: height)
  }
  return CGSize(width: width, height: height)
}

private struct OperatorFlowLayoutRow {
  var indices = [Int]()
  var width: CGFloat = 0
  var height: CGFloat = 0
}
