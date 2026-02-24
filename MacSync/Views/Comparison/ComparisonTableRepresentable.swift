import SwiftUI
import AppKit

struct ComparisonTableRepresentable: NSViewRepresentable {
    let actions: [FileAction]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22
        tableView.allowsMultipleSelection = false
        tableView.headerView = NSTableHeaderView()

        // Action icon column (30px)
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = ""
        actionColumn.width = 30
        actionColumn.minWidth = 30
        actionColumn.maxWidth = 30
        tableView.addTableColumn(actionColumn)

        // Source file column (flexible)
        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "Source"
        sourceColumn.minWidth = 120
        sourceColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(sourceColumn)

        // Arrow column (40px centered)
        let arrowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("arrow"))
        arrowColumn.title = ""
        arrowColumn.width = 40
        arrowColumn.minWidth = 40
        arrowColumn.maxWidth = 40
        tableView.addTableColumn(arrowColumn)

        // Destination file column (flexible)
        let destColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dest"))
        destColumn.title = "Destination"
        destColumn.minWidth = 120
        destColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(destColumn)

        // Size column (80px right-aligned)
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 80
        sizeColumn.maxWidth = 100
        sizeColumn.headerCell.alignment = .right
        tableView.addTableColumn(sizeColumn)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.actions = actions
        context.coordinator.tableView?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var actions: [FileAction]
        weak var tableView: NSTableView?

        init(actions: [FileAction]) {
            self.actions = actions
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            actions.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < actions.count, let column = tableColumn else { return nil }
            let action = actions[row]
            let identifier = column.identifier

            switch identifier.rawValue {
            case "action":
                return makeIconCell(for: action, in: tableView)
            case "source":
                return makeTextCell(text: sourceText(for: action),
                                    color: nsColor(for: action.action),
                                    alignment: .left, in: tableView, identifier: identifier)
            case "arrow":
                return makeTextCell(text: arrowText(for: action.action),
                                    color: nsColor(for: action.action),
                                    alignment: .center, in: tableView, identifier: identifier)
            case "dest":
                return makeTextCell(text: destText(for: action),
                                    color: nsColor(for: action.action),
                                    alignment: .left, in: tableView, identifier: identifier)
            case "size":
                return makeTextCell(text: sizeText(for: action),
                                    color: .secondaryLabelColor,
                                    alignment: .right, in: tableView, identifier: identifier)
            default:
                return nil
            }
        }

        // MARK: - Cell Factories

        private func makeIconCell(for action: FileAction, in tableView: NSTableView) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("actionIcon")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView
                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16)
                ])
            }
            let image = NSImage(systemSymbolName: action.action.systemImage, accessibilityDescription: action.action.displayName)
            cell.imageView?.image = image
            cell.imageView?.contentTintColor = nsColor(for: action.action)
            return cell
        }

        private func makeTextCell(text: String, color: NSColor, alignment: NSTextAlignment,
                                  in tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier) -> NSView {
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingMiddle
                textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            cell.textField?.stringValue = text
            cell.textField?.textColor = color
            cell.textField?.alignment = alignment
            return cell
        }

        // MARK: - Helpers

        private func sourceText(for action: FileAction) -> String {
            switch action.action {
            case .copyRight, .equal, .deleteSource, .conflict:
                return action.relativePath
            case .copyLeft, .deleteDest:
                return ""
            }
        }

        private func destText(for action: FileAction) -> String {
            switch action.action {
            case .copyLeft, .equal, .deleteDest, .conflict:
                return action.relativePath
            case .copyRight, .deleteSource:
                return ""
            }
        }

        private func arrowText(for actionType: ActionType) -> String {
            switch actionType {
            case .copyRight: return "\u{25B6}"     // right-pointing triangle
            case .copyLeft: return "\u{25C0}"      // left-pointing triangle
            case .equal: return "="
            case .deleteSource, .deleteDest: return "\u{2715}" // multiplication X
            case .conflict: return "!"
            }
        }

        private func sizeText(for action: FileAction) -> String {
            if let size = action.sourceSize ?? action.destSize {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            return ""
        }

        private func nsColor(for actionType: ActionType) -> NSColor {
            switch actionType {
            case .copyRight, .copyLeft: return .systemGreen
            case .equal: return .systemGray
            case .deleteSource, .deleteDest: return .systemRed
            case .conflict: return .systemOrange
            }
        }
    }
}
