import AppKit
import Quartz

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var provider: (any PreviewContentProvider)?
    private var loadTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var analysisWorker: Task<FolderAnalysis, Error>?
    private var dataSource: PreviewDataSource?
    private var outlineView: NSOutlineView!
    private var headerIconView: NSImageView!
    private var titleLabel: NSTextField!
    private var countLabel: NSTextField!
    private var spinner: NSProgressIndicator!
    private var whatsInsideSection: NSVisualEffectView!
    private var whatsInsideRows: NSStackView!
    private var analysisSummaryLabel: NSTextField!
    private var importantSection: NSStackView!
    private var importantRows: NSStackView!
    private var fileDetailSection: NSStackView!
    private var fileDetailText: NSTextField!
    private var contentTopToHeader: NSLayoutConstraint!
    private var analysisTopToHeader: NSLayoutConstraint!
    private var contentTopToAnalysis: NSLayoutConstraint!
    private var contentReady = false
    private var contentRevealed = false
    private var hasPresentedContent = false

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        // Quick Look measures the extension at zero size during its source-file
        // zoom. Keep our hierarchy invisible until the host has a real frame;
        // otherwise Auto Layout can briefly paint from the leading edge.
        view.alphaValue = 0
        buildInterface()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        revealContentIfReady()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        cancelLoading()
        hasPresentedContent = false
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Quick Look does not guarantee that a directory URL carries a
        // trailing slash. `hasDirectoryPath` is therefore insufficient here:
        // returning without rendering makes the host silently fall back to
        // Apple's generic folder icon preview. Resolve the directory bit from
        // the filesystem metadata once, then keep that decision stable for the
        // entire load.
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isZIP = url.pathExtension.caseInsensitiveCompare("zip") == .orderedSame
        guard isDirectory || isZIP else { return }
        cancelLoading()

        let contentProvider: any PreviewContentProvider = isDirectory
            ? FolderContentProvider(rootURL: url)
            : ZIPContentProvider(archiveURL: url)
        provider = contentProvider
        let source = await MainActor.run {
            self.loadViewIfNeeded()
            let keepPreviewVisible = self.hasPresentedContent && self.view.window != nil
            self.contentReady = false
            self.contentRevealed = keepPreviewVisible
            if !keepPreviewVisible { self.view.alphaValue = 0 }
            let source = PreviewDataSource(provider: contentProvider)
            source.onChildrenRequested = { [weak self] item in
                self?.loadChildren(of: item)
            }
            source.onRealIconRequested = { [weak self, weak source] item in
                self?.loadRealIcon(for: item, dataSource: source, rootURL: url, isDirectory: isDirectory)
            }
            source.onItemSelected = { [weak self] item in
                self?.presentFileDetails(for: item, rootURL: url, isFilesystemFolder: isDirectory)
            }
            self.dataSource = source
            // Do not ask LaunchServices for a file icon during the preview
            // hand-off. That synchronous lookup can block the Quick Look
            // host while it resolves an application association. SF Symbols
            // are native, deterministic and already available in AppKit.
            self.headerIconView.image = NSImage(
                systemSymbolName: isDirectory ? "folder.fill" : "archivebox",
                accessibilityDescription: nil
            )
            self.titleLabel.stringValue = url.lastPathComponent
            self.countLabel.stringValue = NSLocalizedString("loading", comment: "Preview loading status")
            self.resetAnalysisPresentation()
            self.spinner.isHidden = false
            self.spinner.startAnimation(nil)
            self.outlineView.dataSource = source
            self.outlineView.delegate = source
            self.outlineView.target = self
            self.outlineView.action = #selector(PreviewViewController.handleOutlineRowClick(_:))
            self.outlineView.doubleAction = nil
            self.outlineView.target = self
            return source
        }

        if isDirectory {
            beginFolderAnalysis(at: url, provider: contentProvider)
        }

        loadTask = Task { [weak self, contentProvider] in
            guard let controller = self else { return }
            do {
                let items = try await Task.detached(priority: .userInitiated) {
                    try await contentProvider.loadRoot { partialItems in
                        Task { @MainActor in
                            guard controller.provider === contentProvider else { return }
                            source.setRootItems(partialItems)
                            controller.outlineView.reloadData()
                            controller.updateCountLabel()
                            controller.contentReady = true
                            controller.revealContentIfReady()
                        }
                    }
                }.value
                try Task.checkCancellation()
                await MainActor.run {
                    source.setRootItems(items)
                    controller.outlineView.reloadData()
                    controller.updateCountLabel()
                    controller.spinner.stopAnimation(nil)
                    controller.spinner.isHidden = true
                    controller.contentReady = true
                    controller.revealContentIfReady()
                }
            } catch is CancellationError {
                // Preview was dismissed; no UI work is needed.
            } catch {
                await MainActor.run {
                    let key = isDirectory ? "unable_to_read_folder" : "unable_to_preview_archive"
                    controller.countLabel.stringValue = NSLocalizedString(key, comment: "Preview read error")
                    controller.spinner.stopAnimation(nil)
                    controller.spinner.isHidden = true
                    controller.contentReady = true
                    controller.revealContentIfReady()
                }
            }
        }
    }

    private func loadChildren(of item: PreviewItem) {
        guard let provider else { return }
        Task { [weak self, provider, dataSource] in
            do {
                let children = try await Task.detached(priority: .userInitiated) {
                    try await provider.loadChildren(of: item)
                }.value
                await MainActor.run {
                    guard let self, let dataSource else { return }
                    dataSource.setChildren(children, for: item, in: self.outlineView)
                    // Child rows are materialized lazily by AppKit. Build the
                    // newly visible native row/cell views now, off the user's
                    // next click, so selection stays on the native fast path.
                    self.prewarmVisibleRows()
                }
            } catch {
                await MainActor.run { dataSource?.failLoading(item) }
            }
        }
    }

    @objc private func handleOutlineRowClick(_ sender: NSOutlineView) {
        guard NSApp.currentEvent?.clickCount == 1 else { return }
        let row = sender.clickedRow
        guard row >= 0,
              let item = dataSource?.item(at: row, in: sender),
              let dataSource else { return }
        let point = sender.convert(sender.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let rowRect = sender.rect(ofRow: row)
        let disclosureRect = sender.frameOfOutlineCell(atRow: row)
        guard rowRect.contains(point), !disclosureRect.contains(point) else { return }

        guard item.isFolder else { return }
        dataSource.toggleFolder(item, in: sender)
    }

    private func loadRealIcon(for item: PreviewItem, dataSource: PreviewDataSource?, rootURL: URL, isDirectory: Bool) {
        let isOnDiskFolderChild = isDirectory && !item.relativePath.isEmpty
        Task { [weak self, dataSource] in
            let icon = await Task.detached(priority: .utility) {
                if isOnDiskFolderChild {
                    let fileURL = rootURL.appendingPathComponent(item.relativePath)
                    return FileIconProvider.shared.realIcon(at: fileURL)
                }
                // ZIP entries have no file URL. Resolve a cached LaunchServices
                // icon by UTI/extension instead; this performs no extraction.
                return FileIconProvider.shared.typeIcon(for: item)
            }.value
            guard let self, let dataSource, self.provider != nil else { return }
            dataSource.setRealIcon(icon, for: item, in: self.outlineView)
        }
    }

    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        analysisWorker?.cancel()
        analysisWorker = nil
        provider?.cancel()
        provider = nil
    }

    private func beginFolderAnalysis(at folderURL: URL, provider: any PreviewContentProvider) {
        let worker = Task.detached(priority: .utility) {
            try FolderAnalyzer().analyze(folderURL: folderURL)
        }
        analysisWorker = worker
        analysisTask = Task { [weak self, worker] in
            do {
                let analysis = try await worker.value
                try Task.checkCancellation()
                guard let self, self.provider === provider else { return }
                self.presentFolderAnalysis(analysis)
            } catch is CancellationError {
                // The Quick Look preview closed or was replaced.
            } catch {
                // Folder intelligence is optional; retain the existing tree.
            }
        }
    }

    private func presentFolderAnalysis(_ analysis: FolderAnalysis) {
        let statistics = displayedCategoryStatistics(from: analysis)
        let importantFiles = ImportantFileDetector().detect(in: analysis)
        guard !statistics.isEmpty || !importantFiles.isEmpty else { return }

        whatsInsideRows.arrangedSubviews.forEach {
            whatsInsideRows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for statistic in statistics {
            whatsInsideRows.addArrangedSubview(makeAnalysisRow(for: statistic))
        }
        presentImportantFiles(importantFiles)

        let summaryKey = analysis.scanState.isPartial
            ? "analysis_summary_partial"
            : "analysis_summary_complete"
        analysisSummaryLabel.stringValue = String.localizedStringWithFormat(
            NSLocalizedString(summaryKey, comment: "Bounded folder analysis summary"),
            analysis.analyzedFileCount,
            analysis.analyzedDirectoryCount,
            Self.byteCountFormatter.string(fromByteCount: analysis.totalKnownFileSize)
        )
        contentTopToHeader.isActive = false
        analysisTopToHeader.isActive = true
        contentTopToAnalysis.isActive = true
        whatsInsideSection.isHidden = false
    }

    private func presentImportantFiles(_ files: [ImportantFile]) {
        importantRows.arrangedSubviews.forEach {
            importantRows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard !files.isEmpty else {
            importantSection.isHidden = true
            return
        }
        for importantFile in files {
            let title = NSTextField(labelWithString: importantFile.file.intelligence.fileName)
            title.font = PreviewVisuals.rowFont
            let subtitle = NSTextField(labelWithString: [
                importantFile.file.intelligence.typeName,
                Self.byteCountFormatter.string(fromByteCount: importantFile.file.size)
            ].joined(separator: " · "))
            subtitle.font = PreviewVisuals.metadataFont
            subtitle.textColor = PreviewVisuals.secondaryLabelColor
            let row = NSStackView(views: [title, subtitle])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 1
            importantRows.addArrangedSubview(row)
        }
        importantSection.isHidden = false
    }

    private func presentFileDetails(for item: PreviewItem?, rootURL: URL, isFilesystemFolder: Bool) {
        guard isFilesystemFolder, let item, !item.isFolder else {
            fileDetailSection?.isHidden = true
            return
        }
        let fileURL = rootURL.appendingPathComponent(item.relativePath)
        let intelligence = FileIntelligenceRecognizer().intelligence(for: fileURL)
        var lines = [
            intelligence.fileName,
            "\(NSLocalizedString("detail_type", comment: "File detail type")): \(intelligence.typeName)",
            "\(NSLocalizedString("detail_category", comment: "File detail category")): \(NSLocalizedString(intelligence.category.localizationKey, comment: "File category"))",
            "\(NSLocalizedString("detail_size", comment: "File detail size")): \(Self.byteCountFormatter.string(fromByteCount: item.size ?? 0))"
        ]
        if let purpose = intelligence.purpose {
            lines.append("\(NSLocalizedString("detail_purpose", comment: "File detail purpose")): \(purpose)")
        }
        if intelligence.category == .unknown {
            if let fileExtension = intelligence.fileExtension {
                lines.append("\(NSLocalizedString("detail_extension", comment: "Unknown file extension")): .\(fileExtension)")
            }
            if let identifier = intelligence.systemTypeIdentifier {
                lines.append("UTType: \(identifier)")
            }
        }
        if let modifiedDate = item.modifiedDate {
            lines.append("\(NSLocalizedString("detail_modified", comment: "File detail date")): \(Self.detailDateFormatter.string(from: modifiedDate))")
        }
        fileDetailText.stringValue = lines.joined(separator: "\n")
        fileDetailSection.isHidden = false
    }

    /// Shows at most six rows. When necessary, five dominant categories are
    /// retained and all remaining categories are accurately merged into Other.
    private func displayedCategoryStatistics(from analysis: FolderAnalysis) -> [CategoryStatistic] {
        let statistics = analysis.categoryStatistics
        guard statistics.count > PreviewVisuals.maximumDisplayedCategories else { return statistics }

        let primaryCount = PreviewVisuals.maximumDisplayedCategories - 1
        var result = Array(statistics.prefix(primaryCount))
        let remainder = statistics.dropFirst(primaryCount)
        let otherCount = remainder.reduce(0) { $0 + $1.fileCount }
        let otherSize = remainder.reduce(Int64(0)) { $0 + $1.totalKnownSize }

        if let existingOther = result.firstIndex(where: { $0.category == .unknown }) {
            let current = result[existingOther]
            result[existingOther] = CategoryStatistic(
                category: .unknown,
                fileCount: current.fileCount + otherCount,
                totalKnownSize: current.totalKnownSize + otherSize
            )
        } else {
            result.append(CategoryStatistic(category: .unknown, fileCount: otherCount, totalKnownSize: otherSize))
        }
        return result.sorted(by: categoryStatisticSort)
    }

    private func categoryStatisticSort(_ lhs: CategoryStatistic, _ rhs: CategoryStatistic) -> Bool {
        if lhs.totalKnownSize != rhs.totalKnownSize { return lhs.totalKnownSize > rhs.totalKnownSize }
        if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
        return lhs.category.stableSortOrder < rhs.category.stableSortOrder
    }

    private func makeAnalysisRow(for statistic: CategoryStatistic) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: statistic.category.systemSymbolName, accessibilityDescription: nil)
        icon.contentTintColor = PreviewVisuals.secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString(
            statistic.category.localizationKey,
            comment: "Folder analysis category"
        ))
        title.font = PreviewVisuals.rowFont
        title.lineBreakMode = .byTruncatingTail

        let count = NSTextField(labelWithString: String.localizedStringWithFormat(
            NSLocalizedString("analysis_file_count", comment: "Number of files in category"),
            statistic.fileCount
        ))
        count.font = PreviewVisuals.metadataFont
        count.textColor = PreviewVisuals.secondaryLabelColor
        count.alignment = .right

        let size = NSTextField(labelWithString: Self.byteCountFormatter.string(fromByteCount: statistic.totalKnownSize))
        size.font = PreviewVisuals.metadataFont
        size.textColor = PreviewVisuals.secondaryLabelColor
        size.alignment = .right

        let row = NSStackView(views: [icon, title, NSView(), count, size])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PreviewVisuals.analysisRowSpacing
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: PreviewVisuals.analysisIconSize),
            icon.heightAnchor.constraint(equalToConstant: PreviewVisuals.analysisIconSize),
            count.widthAnchor.constraint(greaterThanOrEqualToConstant: PreviewVisuals.analysisCountWidth),
            size.widthAnchor.constraint(greaterThanOrEqualToConstant: PreviewVisuals.analysisSizeWidth)
        ])
        return row
    }

    private func resetAnalysisPresentation() {
        whatsInsideRows?.arrangedSubviews.forEach {
            whatsInsideRows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        importantRows?.arrangedSubviews.forEach {
            importantRows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        importantSection?.isHidden = true
        fileDetailSection?.isHidden = true
        whatsInsideSection?.isHidden = true
        contentTopToAnalysis?.isActive = false
        analysisTopToHeader?.isActive = false
        contentTopToHeader?.isActive = true
    }

    private func revealContentIfReady() {
        guard contentReady, !contentRevealed,
              view.bounds.width > 240, view.bounds.height > 160 else { return }
        prewarmVisibleRows()
        contentRevealed = true
        if hasPresentedContent {
            view.alphaValue = 1
            return
        }
        hasPresentedContent = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
    }

    private func prewarmVisibleRows() {
        outlineView.layoutSubtreeIfNeeded()
        let visibleRows = outlineView.rows(in: outlineView.visibleRect)
        guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }
        let end = visibleRows.location + visibleRows.length
        for row in visibleRows.location..<end {
            _ = outlineView.rowView(atRow: row, makeIfNecessary: true)
        }
    }

    private func buildInterface() {
        // Resolve AppKit's SF Symbols once while the preview is being created.
        // Without this, the first child-file row can pay symbol registration
        // cost on the same event as the user's first click.
        PreviewDataSource.prewarmPresentationResources()

        headerIconView = NSImageView()
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageScaling = .scaleProportionallyUpOrDown
        headerIconView.imageAlignment = .alignCenter
        headerIconView.image = NSImage(
            systemSymbolName: "folder.fill",
            accessibilityDescription: NSLocalizedString("folder_accessibility_label", comment: "Folder icon accessibility label")
        )

        titleLabel = NSTextField(labelWithString: NSLocalizedString("folder", comment: "Default folder title"))
        titleLabel.font = PreviewVisuals.headerTitleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        countLabel = NSTextField(labelWithString: "")
        countLabel.font = PreviewVisuals.headerSubtitleFont
        countLabel.textColor = PreviewVisuals.secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.maximumNumberOfLines = 1

        let titleStack = NSStackView(views: [titleLabel, countLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = PreviewVisuals.headerTextSpacing

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small

        let header = NSStackView(views: [headerIconView, titleStack, spinner, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = PreviewVisuals.controlSpacing
        header.translatesAutoresizingMaskIntoConstraints = false

        outlineView = NSOutlineView()
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowSizeStyle = .medium
        outlineView.rowHeight = PreviewVisuals.tableRowHeight
        outlineView.autosaveTableColumns = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.allowsTypeSelect = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.floatsGroupRows = false
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.intercellSpacing = PreviewVisuals.tableIntercellSpacing
        outlineView.gridStyleMask = []
        outlineView.backgroundColor = .clear

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = NSLocalizedString("name_column", comment: "Name column title")
        nameColumn.resizingMask = .autoresizingMask
        nameColumn.minWidth = PreviewVisuals.nameColumnMinimumWidth
        nameColumn.width = 300
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeColumn.title = NSLocalizedString("size_column", comment: "Size column title")
        sizeColumn.resizingMask = []
        sizeColumn.width = PreviewVisuals.sizeColumnWidth
        outlineView.addTableColumn(sizeColumn)

        let modifiedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Modified"))
        modifiedColumn.title = NSLocalizedString("modified_column", comment: "Modified column title")
        modifiedColumn.resizingMask = []
        modifiedColumn.width = PreviewVisuals.modifiedColumnWidth
        outlineView.addTableColumn(modifiedColumn)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = outlineView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentPanel = NSVisualEffectView()
        contentPanel.material = .underWindowBackground
        contentPanel.blendingMode = .behindWindow
        contentPanel.state = .followsWindowActiveState
        contentPanel.wantsLayer = true
        contentPanel.layer?.cornerRadius = PreviewVisuals.contentPanelCornerRadius
        contentPanel.layer?.masksToBounds = true
        contentPanel.translatesAutoresizingMaskIntoConstraints = false
        contentPanel.addSubview(scrollView)

        let whatsInsideTitle = NSTextField(labelWithString: NSLocalizedString("whats_inside", comment: "Folder analysis section title"))
        whatsInsideTitle.font = PreviewVisuals.analysisTitleFont
        analysisSummaryLabel = NSTextField(labelWithString: "")
        analysisSummaryLabel.font = PreviewVisuals.metadataFont
        analysisSummaryLabel.textColor = PreviewVisuals.secondaryLabelColor
        analysisSummaryLabel.lineBreakMode = .byTruncatingTail
        analysisSummaryLabel.maximumNumberOfLines = 1
        let analysisHeader = NSStackView(views: [whatsInsideTitle, NSView(), analysisSummaryLabel])
        analysisHeader.orientation = .horizontal
        analysisHeader.alignment = .centerY
        analysisHeader.spacing = PreviewVisuals.controlSpacing

        whatsInsideRows = NSStackView()
        whatsInsideRows.orientation = .vertical
        whatsInsideRows.alignment = .width
        whatsInsideRows.spacing = PreviewVisuals.analysisRowSpacing

        let analysisStack = NSStackView(views: [analysisHeader, whatsInsideRows])
        analysisStack.orientation = .vertical
        analysisStack.alignment = .width
        analysisStack.spacing = PreviewVisuals.analysisHeaderToRowsSpacing
        analysisStack.translatesAutoresizingMaskIntoConstraints = false

        let importantTitle = NSTextField(labelWithString: NSLocalizedString("important_files", comment: "Important files section title"))
        importantTitle.font = PreviewVisuals.analysisTitleFont
        importantRows = NSStackView()
        importantRows.orientation = .vertical
        importantRows.alignment = .leading
        importantRows.spacing = PreviewVisuals.analysisRowSpacing
        importantSection = NSStackView(views: [importantTitle, importantRows])
        importantSection.orientation = .vertical
        importantSection.alignment = .leading
        importantSection.spacing = PreviewVisuals.analysisHeaderToRowsSpacing

        let detailTitle = NSTextField(labelWithString: NSLocalizedString("selected_file", comment: "Selected file section title"))
        detailTitle.font = PreviewVisuals.analysisTitleFont
        fileDetailText = NSTextField(labelWithString: "")
        fileDetailText.font = PreviewVisuals.metadataFont
        fileDetailText.textColor = PreviewVisuals.secondaryLabelColor
        fileDetailText.maximumNumberOfLines = 0
        fileDetailText.lineBreakMode = .byWordWrapping
        fileDetailSection = NSStackView(views: [detailTitle, fileDetailText])
        fileDetailSection.orientation = .vertical
        fileDetailSection.alignment = .leading
        fileDetailSection.spacing = PreviewVisuals.analysisHeaderToRowsSpacing

        analysisStack.addArrangedSubview(importantSection)
        analysisStack.addArrangedSubview(fileDetailSection)

        whatsInsideSection = NSVisualEffectView()
        whatsInsideSection.material = .underWindowBackground
        whatsInsideSection.blendingMode = .behindWindow
        whatsInsideSection.state = .followsWindowActiveState
        whatsInsideSection.wantsLayer = true
        whatsInsideSection.layer?.cornerRadius = PreviewVisuals.contentPanelCornerRadius
        whatsInsideSection.layer?.masksToBounds = true
        whatsInsideSection.translatesAutoresizingMaskIntoConstraints = false
        whatsInsideSection.addSubview(analysisStack)

        view.addSubview(header)
        view.addSubview(whatsInsideSection)
        view.addSubview(contentPanel)
        let headerTrailing = header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreviewVisuals.headerInset)
        headerTrailing.priority = .defaultLow
        let panelTrailing = contentPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreviewVisuals.contentInset)
        panelTrailing.priority = .defaultLow
        let contentBottom = contentPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -PreviewVisuals.contentInset)
        // Quick Look briefly hosts the controller at height 0 while its opening
        // transition is measured. Let the bottom edge yield during that frame;
        // otherwise AppKit logs a required-constraint conflict and visibly snaps.
        contentBottom.priority = .defaultLow
        contentTopToHeader = contentPanel.topAnchor.constraint(
            equalTo: header.bottomAnchor,
            constant: PreviewVisuals.headerToContentSpacing
        )
        analysisTopToHeader = whatsInsideSection.topAnchor.constraint(
            equalTo: header.bottomAnchor,
            constant: PreviewVisuals.headerToContentSpacing
        )
        contentTopToAnalysis = contentPanel.topAnchor.constraint(
            equalTo: whatsInsideSection.bottomAnchor,
            constant: PreviewVisuals.headerToContentSpacing
        )
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: PreviewVisuals.headerInset),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreviewVisuals.headerInset),
            headerTrailing,
            headerIconView.widthAnchor.constraint(equalToConstant: PreviewVisuals.headerIconSize),
            headerIconView.heightAnchor.constraint(equalToConstant: PreviewVisuals.headerIconSize),
            contentTopToHeader,
            contentPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreviewVisuals.contentInset),
            panelTrailing,
            contentBottom,
            scrollView.topAnchor.constraint(equalTo: contentPanel.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentPanel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentPanel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentPanel.bottomAnchor),
            whatsInsideSection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PreviewVisuals.contentInset),
            whatsInsideSection.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PreviewVisuals.contentInset),
            analysisStack.topAnchor.constraint(equalTo: whatsInsideSection.topAnchor, constant: PreviewVisuals.analysisInset),
            analysisStack.leadingAnchor.constraint(equalTo: whatsInsideSection.leadingAnchor, constant: PreviewVisuals.analysisInset),
            analysisStack.trailingAnchor.constraint(equalTo: whatsInsideSection.trailingAnchor, constant: -PreviewVisuals.analysisInset),
            analysisStack.bottomAnchor.constraint(equalTo: whatsInsideSection.bottomAnchor, constant: -PreviewVisuals.analysisInset),
        ])
        resetAnalysisPresentation()
    }

    private func updateCountLabel() {
        guard let dataSource else { return }
        let total = dataSource.rootItems.count
        countLabel.stringValue = String.localizedStringWithFormat(
            NSLocalizedString("item_count", comment: "Number of folder items"),
            total
        )
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

}
