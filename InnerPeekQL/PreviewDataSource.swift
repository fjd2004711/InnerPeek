import AppKit

@MainActor
final class PreviewDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private(set) var rootItems: [PreviewItem] = []
    private var childrenByID: [UUID: [PreviewItem]] = [:]
    private var loadingIDs: Set<UUID> = []
    private var pendingExpansionIDs: Set<UUID> = []
    private var resolvedIcons: [UUID: NSImage] = [:]
    private var requestedIconIDs: Set<UUID> = []
    private let provider: PreviewContentProvider
    var onChildrenRequested: ((PreviewItem) -> Void)?
    var onRealIconRequested: ((PreviewItem) -> Void)?

    static func prewarmPresentationResources() {
        _ = dateFormatter.string(from: Date())
        _ = byteCountFormatter.string(fromByteCount: 0)
        FileIconProvider.shared.prewarm()
    }

    init(provider: PreviewContentProvider) {
        self.provider = provider
    }

    func setRootItems(_ items: [PreviewItem]) {
        rootItems = items
        childrenByID.removeAll(keepingCapacity: true)
        resolvedIcons.removeAll(keepingCapacity: true)
        requestedIconIDs.removeAll(keepingCapacity: true)
    }

    func setRealIcon(_ image: NSImage, for item: PreviewItem, in outlineView: NSOutlineView) {
        resolvedIcons[item.id] = image
        requestedIconIDs.remove(item.id)
        let row = outlineView.row(forItem: item)
        if row >= 0 {
            outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
        }
    }

    func item(at row: Int, in outlineView: NSOutlineView) -> PreviewItem? {
        outlineView.item(atRow: row) as? PreviewItem
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? PreviewItem else { return rootItems.count }
        return childrenByID[item.id]?.count ?? (item.isFolder ? 0 : 0)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let parent = item as? PreviewItem { return childrenByID[parent.id]![index] }
        return rootItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? PreviewItem)?.isFolder ?? false
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        // Loading is initiated in shouldExpandItem, before AppKit changes the
        // visible outline state, so expansion never shows an empty child area.
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let previewItem = item as? PreviewItem, previewItem.isFolder else { return false }
        if childrenByID[previewItem.id] != nil { return true }
        guard !loadingIDs.contains(previewItem.id) else { return false }
        loadingIDs.insert(previewItem.id)
        pendingExpansionIDs.insert(previewItem.id)
        onChildrenRequested?(previewItem)
        return false
    }

    func toggleFolder(_ item: PreviewItem, in outlineView: NSOutlineView) {
        guard item.isFolder else { return }
        if outlineView.isItemExpanded(item) {
            outlineView.animator().collapseItem(item)
            return
        }
        if childrenByID[item.id] != nil {
            outlineView.animator().expandItem(item)
            return
        }
        guard !loadingIDs.contains(item.id) else { return }
        loadingIDs.insert(item.id)
        pendingExpansionIDs.insert(item.id)
        onChildrenRequested?(item)
    }

    func setChildren(_ children: [PreviewItem], for item: PreviewItem, in outlineView: NSOutlineView) {
        loadingIDs.remove(item.id)
        childrenByID[item.id] = children
        let shouldExpand = pendingExpansionIDs.remove(item.id) != nil
        if shouldExpand {
            // The model is complete before the outline opens, avoiding the
            // visible empty-row -> sudden-population jump.
            // Use AppKit's animator proxy even for the first, lazy-loaded
            // expansion. The synchronous API skips the outline row animation;
            // cached re-expansions already use AppKit's animated path, which
            // is why the first open previously felt different from later ones.
            outlineView.animator().expandItem(item)
        } else {
            outlineView.reloadItem(item, reloadChildren: true)
        }
    }

    func failLoading(_ item: PreviewItem) {
        loadingIDs.remove(item.id)
        pendingExpansionIDs.remove(item.id)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is PreviewItem
    }

    @objc func handleRowClick(_ sender: NSOutlineView) {
        let row = sender.clickedRow
        guard row >= 0,
              let previewItem = sender.item(atRow: row) as? PreviewItem,
              previewItem.isFolder else { return }

        // Keep the native disclosure triangle. The outline action also fires
        // for AX/trackpad row clicks, so the whole name row gets the same
        // toggle behavior without replacing mouse handling.
        let point = sender.convert(sender.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let rowRect = sender.rect(ofRow: row)
        guard rowRect.contains(point), point.x - rowRect.minX > 24 else { return }
        toggleFolder(previewItem, in: sender)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let previewItem = item as? PreviewItem else { return nil }
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("Name")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.font = identifier.rawValue == "Name" ? PreviewVisuals.rowFont : PreviewVisuals.metadataFont
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            cell.addSubview(field)
            cell.textField = field
            if identifier.rawValue == "Name" {
                let iconView = NSImageView()
                iconView.translatesAutoresizingMaskIntoConstraints = false
                iconView.imageScaling = .scaleProportionallyUpOrDown
                iconView.imageAlignment = .alignCenter
                cell.imageView = iconView
                cell.addSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: 18),
                    iconView.heightAnchor.constraint(equalToConstant: 18),
                    field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
        }

        switch identifier.rawValue {
        case "Size":
            cell.textField?.alignment = .right
            cell.textField?.stringValue = previewItem.size.map { Self.byteCountFormatter.string(fromByteCount: $0) } ?? "—"
        case "Modified":
            cell.textField?.alignment = .left
            cell.textField?.stringValue = previewItem.modifiedDate.map(Self.dateFormatter.string(from:)) ?? "—"
        default:
            cell.textField?.alignment = .left
            cell.textField?.stringValue = previewItem.name
            cell.imageView?.image = resolvedIcons[previewItem.id] ?? FileIconProvider.shared.icon(for: previewItem)
            if resolvedIcons[previewItem.id] == nil,
               (!previewItem.isFolder || !previewItem.relativePath.isEmpty),
               requestedIconIDs.insert(previewItem.id).inserted {
                onRealIconRequested?(previewItem)
            }
        }
        return cell
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

}
