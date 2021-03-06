import Foundation
import CoreSpotlight
import UIKit
import SimplenoteSearch


// MARK: - View Lifecycle
//
extension SPNoteListViewController {

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let popoverController = self?.popoverController, let sortBar = self?.sortBar else {
                return
            }

            popoverController.sourceRect = sortBar.dividerView.frame
        }, completion: nil)
    }
}


// MARK: - Components Initialization
//
extension SPNoteListViewController {

    /// Sets up the Feedback Generator!
    ///
    @objc
    func configureImpactGenerator() {
        feedbackGenerator = UIImpactFeedbackGenerator()
        feedbackGenerator.prepare()
    }

    /// Sets up the main TableView
    ///
    @objc
    func configureTableView() {
        assert(tableView == nil, "tableView is already initialized!")

        tableView = UITableView()
        tableView.delegate = self

        tableView.alwaysBounceVertical = true
        tableView.tableFooterView = UIView()

        tableView.layoutMargins = .zero
        tableView.separatorInset = .zero
        tableView.separatorInsetReference = .fromAutomaticInsets
        tableView.separatorStyle = UIDevice.sp_isPad() ? .none : .singleLine

        tableView.register(SPNoteTableViewCell.loadNib(), forCellReuseIdentifier: SPNoteTableViewCell.reuseIdentifier)
        tableView.register(SPTagTableViewCell.loadNib(), forCellReuseIdentifier: SPTagTableViewCell.reuseIdentifier)
        tableView.register(SPSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SPSectionHeaderView.reuseIdentifier)
    }

    /// Sets up the Sort Bar
    ///
    @objc
    func configureSortBar() {
        sortBar = SPSortBar.instantiateFromNib()

        sortBar.isHidden = true
        sortBar.onSortModePress = { [weak self] in
            self?.sortModeWasPressed()
        }

        sortBar.onSortOrderPress = { [weak self] in
            self?.sortOrderWasPressed()
        }
    }

    /// Sets up the Results Controller
    ///
    @objc
    func configureResultsController() {
        assert(notesListController == nil, "listController is already initialized!")

        notesListController = NotesListController(viewContext: SPAppDelegate.shared().managedObjectContext)
        notesListController.performFetch()
    }

    /// Sets up the Placeholder View
    ///
    @objc
    func configurePlaceholderView() {
        placeholderView = SPPlaceholderView()
        placeholderView.isUserInteractionEnabled = false

        placeholderView.imageView.image = .image(name: .simplenoteLogo)
        placeholderView.imageView.tintColor = .simplenotePlaceholderImageColor

        placeholderView.textLabel.textColor = .simplenotePlaceholderTextColor
    }

    /// Sets up the Search StackView
    /// - Note: We're embedding the SearchBar inside a StackView, to aid in the SearchBar-Hidden Mechanism
    ///
    @objc
    func configureSearchStackView() {
        assert(searchBar != nil, "searchBar must be initialized first!")

        searchBarStackView = UIStackView(arrangedSubviews: [searchBar])
        searchBarStackView.axis = .vertical
    }

    /// Sets up the Root ViewController
    ///
    @objc
    func configureRootView() {
        navigationBarBackground.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        searchBarStackView.translatesAutoresizingMaskIntoConstraints = false
        sortBar.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(placeholderView)
        view.addSubview(navigationBarBackground)
        view.addSubview(searchBarStackView)
        view.addSubview(sortBar)

        NSLayoutConstraint.activate([
            searchBarStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBarStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.searchBarInsets.left),
            searchBarStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: Constants.searchBarInsets.right)
        ])

        NSLayoutConstraint.activate([
            navigationBarBackground.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarBackground.leftAnchor.constraint(equalTo: view.leftAnchor),
            navigationBarBackground.rightAnchor.constraint(equalTo: view.rightAnchor),
            navigationBarBackground.bottomAnchor.constraint(equalTo: searchBarStackView.bottomAnchor)
        ])

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            placeholderView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        NSLayoutConstraint.activate([
            sortBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sortBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sortBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Initializes the UITableView <> NoteListController Link. Should be called once both UITableView + ListController have been initialized
    ///
    @objc
    func startDisplayingEntities() {
        tableView.dataSource = self

        notesListController.onBatchChanges = { [weak self] (sectionsChangeset, objectsChangeset) in
            guard let `self` = self else {
                return
            }

            /// Note:
            ///  1. State Restoration might cause this ViewController not to be onScreen
            ///  2. When that happens, any remote change might cause a Batch Update
            ///  3. And the above yields a crash
            ///
            /// In this snipept we're preventing a beautiful `_Bug_Detected_In_Client_Of_UITableView_Invalid_Number_Of_Rows_In_Section` exception
            ///
            guard let _ = self.view.window else {
                self.tableView.reloadData()
                return
            }

            self.tableView.performBatchChanges(sectionsChangeset: sectionsChangeset, objectsChangeset: objectsChangeset) { _ in
                self.displayPlaceholdersIfNeeded()
            }
        }
    }
}


// MARK: - Internal Methods
//
extension SPNoteListViewController {

    /// Adjust the TableView's Insets, so that the content falls below the searchBar
    ///
    @objc
    func refreshTableViewTopInsets() {
        tableView.contentInset.top = searchBarStackView.frame.height
        tableView.scrollIndicatorInsets.top = searchBarStackView.frame.height
    }

    /// Scrolls to the First Row whenever the flag `mustScrollToFirstRow` was set to true
    ///
    @objc
    func ensureFirstRowIsVisibleIfNeeded() {
        guard mustScrollToFirstRow else {
            return
        }

        ensureFirstRowIsVisible()
        mustScrollToFirstRow = false
    }

    /// Workaround: Scroll to the very first row. Expected to be called *just* once, right after the view has been laid out, and has been moved
    /// to its parent ViewController.
    ///
    /// Ref. Issue #452
    ///
    @objc
    func ensureFirstRowIsVisible() {
        guard !tableView.isHidden else {
            return
        }

        tableView.contentOffset.y = tableView.adjustedContentInset.top * -1
    }

    /// Registers the ListViewController for Peek and Pop events.
    ///
    @objc
    func registerForPeekAndPop() {
        registerForPreviewing(with: self, sourceView: tableView)
    }

    /// Refreshes the Notes ListController Filters + Sorting: We'll also update the UI (TableView + Title) to match the new parameters.
    ///
    @objc
    func refreshListController() {
        let selectedTag = SPAppDelegate.shared().selectedTag
        let filter = NotesListFilter(selectedTag: selectedTag)

        notesListController.filter = filter
        notesListController.sortMode = Options.shared.listSortMode
        notesListController.searchSortMode = Options.shared.searchSortMode
        notesListController.performFetch()

        tableView.reloadData()
    }

    /// Refreshes the receiver's Title, to match the current filter
    ///
    @objc
    func refreshTitle() {
        title = searchController.active ? NSLocalizedString("Search", comment: "Search Title") : notesListController.filter.title
    }

    /// Toggles the SearchBar's Visibility, based on the active Filter.
    ///
    /// - Note: We're marking `mustScrollToFirstRow`, which will cause the layout pass to run `ensureFirstRowIsVisible`.
    ///         Changing the SearchBar Visibility triggers a layout pass, which updates the Table's Insets, and scrolls up to the first row.
    ///
    @objc
    func refreshSearchBar() {
        guard searchBar.isHidden != isDeletedFilterActive else {
            return
        }

        mustScrollToFirstRow = true
        searchBar.isHidden = isDeletedFilterActive
    }

    /// Refreshes the SearchBar's Text (and backfires the NoteListController filtering mechanisms!)
    ///
    func refreshSearchText(appendFilterFor tag: Tag) {
        let keyword = String.searchOperatorForTags + tag.name
        let updated = searchBar.text?.replaceLastWord(with: keyword) ?? keyword

        searchController.updateSearchText(searchText: updated + .space)
    }

    /// Refreshes the SortBar's Description Text
    ///
    @objc
    func refreshSortBarText() {
        sortBar.descriptionText = Options.shared.searchSortMode.description
    }

    /// Displays the Emtpy State Placeholders, when / if needed
    ///
    @objc
    func displayPlaceholdersIfNeeded() {
        guard isListEmpty else {
            placeholderView.isHidden = true
            return
        }

        placeholderView.isHidden = false
        placeholderView.displayMode = {
            if isIndexingNotes || SPAppDelegate.shared().bSigningUserOut {
                return .picture
            }

            return isSearchActive ? .text : .pictureAndText
        }()

        placeholderView.textLabel.text = {
            if isSearchActive {
                return NSLocalizedString("No Results", comment: "Message shown when no notes match a search string")
            }

            return NSLocalizedString("No Notes", comment: "Message shown in note list when no notes are in the current view")
        }()
    }

    /// Indicates if the Deleted Notes are onScreen
    ///
    @objc
    var isDeletedFilterActive: Bool {
        return notesListController.filter == .deleted
    }

    /// Indicates if the List is Empty
    ///
    @objc
    var isListEmpty: Bool {
        return notesListController.numberOfObjects <= 0
    }

    /// Indicates if we're in Search Mode
    ///
    @objc
    var isSearchActive: Bool {
        return searchController.active
    }

    /// Returns the SearchText
    ///
    @objc
    var searchText: String? {
        guard case let .searching(keyword) = notesListController.state else {
            return nil
        }

        return keyword
    }
}


// MARK: - UIViewControllerPreviewingDelegate Conformance
//
extension SPNoteListViewController: UIViewControllerPreviewingDelegate {

    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard tableView.isUserInteractionEnabled,
            isDeletedFilterActive == false,
            let indexPath = tableView.indexPathForRow(at: location),
            let note = notesListController.object(at: indexPath) as? Note
            else {
                return nil
        }

        /// Prevent any Pan gesture from passing thru
        SPAppDelegate.shared().sidebarViewController.requirePanningToFail()

        /// Mark the source of the interaction
        previewingContext.sourceRect = tableView.rectForRow(at: indexPath)

        /// Setup the Editor
        return previewingViewController(for: note)
    }

    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        guard let editorViewController = viewControllerToCommit as? SPNoteEditorViewController else {
            return
        }

        editorViewController.isPreviewing = false
        navigationController?.pushViewController(editorViewController, animated: true)
    }
}


// MARK: - UIScrollViewDelegate
//
extension SPNoteListViewController: UIScrollViewDelegate {

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard searchBar.isFirstResponder, searchBar.text?.isEmpty == false else {
            return
        }

        searchBar.resignFirstResponder()
    }
}


// MARK: - UITableViewDataSource
//
extension SPNoteListViewController: UITableViewDataSource {

    public func numberOfSections(in tableView: UITableView) -> Int {
        return notesListController.sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return notesListController.sections[section].numberOfObjects
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch notesListController.object(at: indexPath) {
        case let note as Note:
            return dequeueAndConfigureCell(for: note, in: tableView, at: indexPath)
        case let tag as Tag:
            return dequeueAndConfigureCell(for: tag, in: tableView, at: indexPath)
        default:
            fatalError()
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = notesListController.sections[section]
        guard section.displaysTitle else {
            return nil
        }

        return section.title
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard notesListController.sections[section].displaysTitle else {
            return nil
        }

        return tableView.dequeueReusableHeaderFooterView(ofType: SPSectionHeaderView.self)
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}


// MARK: - UITableViewDelegate
//
extension SPNoteListViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // Notes:
        //  1.  No need to estimate. We precalculate the Height elsewhere, and we can return the *Actual* value
        //  2.  We always scroll to the first row whenever Search Results are updated. If we don't implement this method,
        //      UITableView ends up jumping off elsewhere!
        //
        return self.tableView(tableView, heightForRowAt: indexPath)
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch notesListController.object(at: indexPath) {
        case is Note:
            return noteRowHeight
        case is Tag:
            return tagRowHeight
        default:
            return .zero
        }
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        guard notesListController.sections[section].displaysTitle else {
            return .leastNormalMagnitude
        }

        return Constants.estimatedHeightForHeaderInSection
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard notesListController.sections[section].displaysTitle else {
            return .leastNormalMagnitude
        }

        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Swipeable Actions: Only enabled for Notes
        guard let note = notesListController.object(at: indexPath) as? Note else {
            return nil
        }

        return UISwipeActionsConfiguration(actions: contextActions(for: note))
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch notesListController.object(at: indexPath) {
        case let note as Note:
            SPRatingsHelper.sharedInstance()?.incrementSignificantEvent()
            open(note, animated: true)
        case let tag as Tag:
            refreshSearchText(appendFilterFor: tag)
        default:
            break
        }
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard isDeletedFilterActive == false, let note = notesListController.object(at: indexPath) as? Note else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            return self.previewingViewController(for: note)

        }, actionProvider: { suggestedActions in
            return self.contextMenu(for: note)
        })
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let editorViewController = animator.previewViewController as? SPNoteEditorViewController else {
            return
        }

        animator.addCompletion {
            editorViewController.isPreviewing = false
            self.show(editorViewController, sender: self)
        }
    }
}


// MARK: - TableViewCell(s) Initialization
//
private extension SPNoteListViewController {

    /// Returns a UITableViewCell configured to display the specified Note
    ///
    func dequeueAndConfigureCell(for note: Note, in tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(ofType: SPNoteTableViewCell.self, for: indexPath)

        note.ensurePreviewStringsAreAvailable()

        cell.accessibilityLabel = note.titlePreview
        cell.accessibilityHint = NSLocalizedString("Open note", comment: "Select a note to view in the note editor")

        cell.accessoryLeftImage = note.pinned ? .image(name: .pinSmall) : nil
        cell.accessoryRightImage = note.published ? .image(name: .shared) : nil
        cell.accessoryLeftTintColor = .simplenoteNotePinStatusImageColor
        cell.accessoryRightTintColor = .simplenoteNoteShareStatusImageColor

        cell.rendersInCondensedMode = Options.shared.condensedNotesList
        cell.titleText = note.titlePreview
        cell.bodyText = note.bodyPreview

        cell.keywords = searchText
        cell.keywordsTintColor = .simplenoteTintColor

        cell.prefixText = prefixText(for: note)

        cell.refreshAttributedStrings()

        return cell
    }

    /// Returns a UITableViewCell configured to display the specified Tag
    ///
    func dequeueAndConfigureCell(for tag: Tag, in tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(ofType: SPTagTableViewCell.self, for: indexPath)
        cell.leftImage = .image(name: .tag)
        cell.leftImageTintColor = .simplenoteNoteShareStatusImageColor
        cell.titleText = String.searchOperatorForTags + tag.name
        return cell
    }

    /// Returns the Prefix for a given note: We'll prepend the (Creation / Modification) Date, whenever we're in Search, and the Sort Option is relevant
    ///
    func prefixText(for note: Note) -> String? {
        guard case .searching = notesListController.state,
            let date = note.date(for: notesListController.searchSortMode)
            else {
                return nil
        }

        return DateFormatter.listDateFormatter.string(from: date)
    }
}


// MARK: - Row Actions
//
private extension SPNoteListViewController {

    func contextActions(for note: Note) -> [UIContextualAction] {
        if note.deleted {
            return deletedContextActions(for: note)
        }

        return regularContextActions(for: note)
    }

    func deletedContextActions(for note: Note) -> [UIContextualAction] {
        return [
            UIContextualAction(style: .normal, image: .image(name: .restore), backgroundColor: .simplenoteRestoreActionColor) { (_, _, completion) in
                SPObjectManager.shared().restoreNote(note)
                CSSearchableIndex.default().indexSearchableNote(note)
                completion(true)
            },

            UIContextualAction(style: .destructive, image: .image(name: .trash), backgroundColor: .simplenoteDestructiveActionColor) { (_, _, completion) in
                SPTracker.trackListNoteDeleted()
                SPObjectManager.shared().permenentlyDeleteNote(note)
                completion(true)
            }
        ]
    }

    func regularContextActions(for note: Note) -> [UIContextualAction] {
        let pinImageName: UIImageName = note.pinned ? .unpin : .pin

        return [
            UIContextualAction(style: .destructive, image: .image(name: .trash), backgroundColor: .simplenoteDestructiveActionColor) { [weak self] (_, _, completion) in
                self?.delete(note: note)
                completion(true)
            },

            UIContextualAction(style: .normal, image: .image(name: pinImageName), backgroundColor: .simplenoteSecondaryActionColor) { [weak self] (_, _, completion) in
                self?.togglePinnedState(note: note)
                completion(true)
            },

            UIContextualAction(style: .normal, image: .image(name: .link), backgroundColor: .simplenoteTertiaryActionColor) { [weak self] (_, _, completion) in
                self?.copyInternalLink(to: note)
                completion(true)
            },

            UIContextualAction(style: .normal, image: .image(name: .share), backgroundColor: .simplenoteQuaternaryActionColor) { [weak self] (_, _, completion) in
                self?.share(note: note)
                completion(true)
            }
        ]
    }
}


// MARK: - UIMenu
//
@available(iOS 13.0, *)
private extension SPNoteListViewController {

    /// Invoked by the Long Press UITableView Mechanism (ex 3d Touch)
    ///
    func contextMenu(for note: Note) -> UIMenu {
        let copy = UIAction(title: ActionTitle.copyLink, image: .image(name: .link)) { [weak self] _ in
            self?.copyInternalLink(to: note)
        }

        let share = UIAction(title: ActionTitle.share, image: .image(name: .share)) { [weak self] _ in
            self?.share(note: note)
        }

        let pinTitle = note.pinned ? ActionTitle.unpin : ActionTitle.pin
        let pin = UIAction(title: pinTitle, image: .image(name: .pin)) { [weak self] _ in
            self?.togglePinnedState(note: note)
        }

        /// NOTE:
        /// iOS 13 exhibits a broken animation when performing a Delete OP from a ContextMenu.
        /// Since this appears to be fixed in iOS 14, quick workaround is: remove Delete from the Contextual Actions for iOS 13.
        ///
        /// Ref.: https://github.com/Automattic/simplenote-ios/pull/902/files
        ///
        guard #available(iOS 14.0, *) else {
            return UIMenu(title: "", children: [share, copy, pin])
        }

        let delete = UIAction(title: ActionTitle.delete, image: .image(name: .trash), attributes: .destructive) { [weak self] _ in
            self?.delete(note: note)
        }

        return UIMenu(title: "", children: [share, copy, pin, delete])
    }
}


// MARK: - Services
//
private extension SPNoteListViewController {

    func delete(note: Note) {
        SPTracker.trackListNoteDeleted()
        SPObjectManager.shared().trashNote(note)
        CSSearchableIndex.default().deleteSearchableNote(note)
    }

    func copyInternalLink(to note: Note) {
        SPTracker.trackListCopiedInternalLink()
        UIPasteboard.general.copyInternalLink(to: note)
    }

    func togglePinnedState(note: Note) {
        SPTracker.trackListPinToggled()
        SPObjectManager.shared().updatePinnedState(!note.pinned, note: note)
    }

    func share(note: Note) {
        guard let _ = note.content, let activityController = UIActivityViewController(note: note) else {
            return
        }

        SPTracker.trackEditorNoteContentShared()

        guard UIDevice.sp_isPad(), let indexPath = notesListController.indexPath(forObject: note) else {
            present(activityController, animated: true, completion: nil)
            return
        }

        activityController.modalPresentationStyle = .popover

        let presentationController = activityController.popoverPresentationController
        presentationController?.permittedArrowDirections = .any
        presentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        presentationController?.sourceView = tableView

        present(activityController, animated: true, completion: nil)
    }

    func previewingViewController(for note: Note) -> SPNoteEditorViewController {
        let editorViewController = EditorFactory.shared.build()
        editorViewController.display(note)
        editorViewController.isPreviewing = true
        editorViewController.searchString = searchText

        return editorViewController
    }
}


// MARK: - Sort Bar
//
extension SPNoteListViewController {

    @objc
    func displaySortBar() {
        // No need to refresh the Table's Bottom Insets. The keyboard will always show!
        sortBar.animateVisibility(isHidden: false)
    }

    @objc
    func dismissSortBar() {
        // We'll need to refresh the bottom insets. The keyboard may have been dismissed already!
        sortBar.animateVisibility(isHidden: true)
        refreshTableViewBottomInsets()
    }
}


// MARK: - Keyboard Handling
//
extension SPNoteListViewController {

    @objc(keyboardWillChangeFrame:)
    func keyboardWillChangeFrame(note: Notification) {
        
        guard let _ = view.window else {
            // No window means we aren't in the view hierarchy.
            // Asking UITableView to refresh layout when not in the view hierarcy results in console warnings.
            return
        }
        
        guard let keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }

        keyboardHeight = keyboardFrame.intersection(view.frame).height
        refreshTableViewBottomInsets()
    }

    func refreshTableViewBottomInsets() {
        let bottomInsets = bottomInsetsForTableView

        UIView.animate(withDuration: UIKitConstants.animationShortDuration) {
            self.tableView.contentInset.bottom = bottomInsets
            self.tableView.scrollIndicatorInsets.bottom = bottomInsets
            self.view.layoutIfNeeded()
        }
    }

    var bottomInsetsForTableView: CGFloat {
        // Keyboard offScreen + Search Active: Seriously, consider the Search Bar
        guard keyboardHeight > .zero else {
            return isSearchActive ? sortBar.frame.height : .zero
        }

        // Keyboard onScreen: the SortBar falls below the keyboard
        return keyboardHeight
    }
}


// MARK: - Search Action Handlers
//
extension SPNoteListViewController {

    @IBAction
    func sortOrderWasPressed() {
        feedbackGenerator.impactOccurred()
        Options.shared.searchSortMode = notesListController.searchSortMode.inverse
    }

    @IBAction
    func sortModeWasPressed() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for mode in [SortMode.alphabeticallyAscending, .createdNewest, .modifiedNewest] {
            alertController.addDefaultActionWithTitle(mode.kind) { _ in
                Options.shared.searchSortMode = mode
            }
        }

        alertController.addCancelActionWithTitle(ActionTitle.cancel)

        let popoverPresentationController = alertController.popoverPresentationController
        popoverPresentationController?.sourceRect = sortBar.dividerView.frame
        popoverPresentationController?.sourceView = sortBar.dividerView
        popoverPresentationController?.permittedArrowDirections = .any
        self.popoverController = popoverPresentationController

        feedbackGenerator.impactOccurred()
        present(alertController, animated: true, completion: nil)
    }
}


// MARK: - Private Types
//
private enum ActionTitle {
    static let cancel = NSLocalizedString("Cancel", comment: "Dismissing an interface")
    static let copyLink = NSLocalizedString("Copy Link", comment: "Copies Link to a Note")
    static let delete = NSLocalizedString("Move to Trash", comment: "Deletes a note")
    static let pin = NSLocalizedString("Pin to Top", comment: "Pins a note")
    static let share = NSLocalizedString("Share...", comment: "Shares a note")
    static let unpin = NSLocalizedString("Unpin", comment: "Unpins a note")
}

private enum Constants {

    /// Section Header's Estimated Height
    ///
    static let estimatedHeightForHeaderInSection = CGFloat(30)

    /// Where do these insets come from?
    /// `For other subviews in your view hierarchy, the default layout margins are normally 8 points on each side`
    ///
    /// We're replicating the (old) view herarchy's behavior, in which the SearchBar would actually be contained within a view with 8pt margins on each side.
    /// This won't be required anymore *soon*, and it's just a temporary workaround.
    ///
    /// Ref. https://developer.apple.com/documentation/uikit/uiview/1622566-layoutmargins
    ///
    static let searchBarInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
}
