import Foundation


// MARK: - Note
//
extension Note {

    /// Indicates if the receiver is a blank document
    ///
    @objc
    var isBlank: Bool {
        objectID.isTemporaryID && content?.count == .zero && tagsArray?.count == .zero
    }

    /// Returns the Creation / Modification date for a given SortMode
    ///
    func date(for sortMode: SortMode) -> Date? {
        switch sortMode {
        case .alphabeticallyAscending, .alphabeticallyDescending:
            return nil

        case .createdNewest, .createdOldest:
            return creationDate

        case .modifiedNewest, .modifiedOldest:
            return modificationDate
        }
    }

    /// Returns the collection user emails with who we're sharing this document
    ///
    var emailTags: [String] {
        guard let tags = tagsArray as? [String] else {
            return []
        }

        return tags.filter {
            $0.isValidEmailAddress
        }
    }
}
