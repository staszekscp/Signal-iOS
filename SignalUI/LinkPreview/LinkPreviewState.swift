//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import YYImage

public enum LinkPreviewImageState {
    case none
    case loading
    case loaded
    case invalid
}

// MARK: -

public struct LinkPreviewImageCacheKey: Hashable, Equatable {
    public let id: TSResourceId?
    public let urlString: String?
    public let thumbnailQuality: AttachmentThumbnailQuality

    public init(id: TSResourceId?, urlString: String?, thumbnailQuality: AttachmentThumbnailQuality) {
        self.id = id
        self.urlString = urlString
        self.thumbnailQuality = thumbnailQuality
    }
}

public protocol LinkPreviewState: AnyObject {
    var isLoaded: Bool { get }
    var urlString: String? { get }
    var displayDomain: String? { get }
    var title: String? { get }
    var imageState: LinkPreviewImageState { get }
    func imageAsync(
        thumbnailQuality: AttachmentThumbnailQuality,
        completion: @escaping (UIImage) -> Void
    )
    func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey?
    var imagePixelSize: CGSize { get }
    var previewDescription: String? { get }
    var date: Date? { get }
    var isGroupInviteLink: Bool { get }
    var isCallLink: Bool { get }
    var activityIndicatorStyle: UIActivityIndicatorView.Style { get }
    var conversationStyle: ConversationStyle? { get }
}

// MARK: -

extension LinkPreviewState {
    var hasLoadedImage: Bool {
        isLoaded && imageState == .loaded
    }
}

// MARK: -

public enum LinkPreviewLinkType {
    case preview
    case incomingMessage
    case outgoingMessage
    case incomingMessageGroupInviteLink
    case outgoingMessageGroupInviteLink
}

// MARK: -

public class LinkPreviewLoading: LinkPreviewState {

    public let linkType: LinkPreviewLinkType

    public init(linkType: LinkPreviewLinkType) {
        self.linkType = linkType
    }

    public var isLoaded: Bool { false }

    public var urlString: String? { nil }

    public var displayDomain: String? { return nil }

    public var title: String? { nil }

    public var imageState: LinkPreviewImageState { .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsFailDebug("Should not be called.")
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        owsFailDebug("Should not be called.")
        return nil
    }

    public var imagePixelSize: CGSize { .zero }

    public var previewDescription: String? { nil }

    public var date: Date? { nil }

    public var isGroupInviteLink: Bool {
        switch linkType {
        case .incomingMessageGroupInviteLink, .outgoingMessageGroupInviteLink:
            return true
        default:
            return false
        }
    }

    public let isCallLink: Bool = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        switch linkType {
        case .incomingMessageGroupInviteLink:
            return .medium
        case .outgoingMessageGroupInviteLink:
            return .medium
        default:
            return LinkPreviewView.defaultActivityIndicatorStyle
        }
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

public class LinkPreviewDraft: LinkPreviewState {

    let linkPreviewDraft: OWSLinkPreviewDraft

    public init(linkPreviewDraft: OWSLinkPreviewDraft) {
        self.linkPreviewDraft = linkPreviewDraft
    }

    public var isLoaded: Bool { true }

    public var urlString: String? { linkPreviewDraft.urlString }

    public var displayDomain: String? {
        guard let displayDomain = linkPreviewDraft.displayDomain else {
            owsFailDebug("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public var title: String? { linkPreviewDraft.title?.nilIfEmpty }

    public var imageState: LinkPreviewImageState { linkPreviewDraft.imageData != nil ? .loaded : .none }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)
        guard let imageData = linkPreviewDraft.imageData else {
            owsFailDebug("Missing imageData.")
            return
        }
        DispatchQueue.global().async {
            guard let image = UIImage(data: imageData) else {
                owsFailDebug("Could not load image: \(imageData.count)")
                return
            }
            completion(image)
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        guard let urlString = urlString else {
            owsFailDebug("Missing urlString.")
            return nil
        }
        return .init(id: nil, urlString: urlString, thumbnailQuality: thumbnailQuality)
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil, lock: .sharedGlobal)

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState == .loaded)
        guard let imageData = linkPreviewDraft.imageData else {
            owsFailDebug("Missing imageData.")
            return .zero
        }
        let imageMetadata = imageData.imageMetadata(withPath: nil, mimeType: nil)
        guard imageMetadata.isValid else {
            owsFailDebug("Invalid image.")
            return .zero
        }
        let imagePixelSize = imageMetadata.pixelSize
        guard imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            owsFailDebug("Invalid image size.")
            return .zero
        }
        let result = imagePixelSize
        imagePixelSizeCache.set(result)
        return result
    }

    public var previewDescription: String? { linkPreviewDraft.previewDescription }

    public var date: Date? { linkPreviewDraft.date }

    public let isGroupInviteLink = false
    public let isCallLink: Bool = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

public class LinkPreviewSent: LinkPreviewState {

    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSResource?

    public let conversationStyle: ConversationStyle?

    public init(
        linkPreview: OWSLinkPreview,
        imageAttachment: TSResource?,
        conversationStyle: ConversationStyle?
    ) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        self.conversationStyle = conversationStyle
    }

    public var isLoaded: Bool { true }

    public var urlString: String? {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url")
            return nil
        }
        return urlString
    }

    public var displayDomain: String? {
        guard let displayDomain = linkPreview.displayDomain else {
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public var title: String? { linkPreview.title?.filterForDisplay.nilIfEmpty }

    public var imageState: LinkPreviewImageState {
        guard let imageAttachment = imageAttachment else {
            return .none
        }
        guard let attachmentStream = imageAttachment.asResourceStream() else {
            return .loading
        }
        switch attachmentStream.computeContentType() {
        case .image, .animatedImage:
            break
        default:
            return .invalid
        }
        return .loaded
    }

    public func imageAsync(thumbnailQuality: AttachmentThumbnailQuality, completion: @escaping (UIImage) -> Void) {
        owsAssertDebug(imageState == .loaded)
        guard let attachmentStream = imageAttachment?.asResourceStream() else {
            owsFailDebug("Could not load image.")
            return
        }
        DispatchQueue.global().async {
            switch attachmentStream.computeContentType() {
            case .animatedImage:
                guard let image = try? attachmentStream.decryptedYYImage() else {
                    owsFailDebug("Could not load image")
                    return
                }
                completion(image)
            case .image:
                Task {
                    guard let image = await attachmentStream.thumbnailImage(quality: thumbnailQuality) else {
                        owsFailDebug("Could not load thumnail.")
                        return
                    }
                    completion(image)
                }
            default:
                owsFailDebug("Invalid image.")
                return
            }
        }
    }

    public func imageCacheKey(thumbnailQuality: AttachmentThumbnailQuality) -> LinkPreviewImageCacheKey? {
        guard let attachmentStream = imageAttachment?.asResourceStream() else {
            return nil
        }
        return .init(id: attachmentStream.resourceId, urlString: nil, thumbnailQuality: thumbnailQuality)
    }

    private let imagePixelSizeCache = AtomicOptional<CGSize>(nil, lock: .sharedGlobal)

    public var imagePixelSize: CGSize {
        if let cachedValue = imagePixelSizeCache.get() {
            return cachedValue
        }
        owsAssertDebug(imageState == .loaded)
        guard let attachmentStream = imageAttachment?.asResourceStream() else {
            return CGSize.zero
        }

        let result: CGSize = {
            switch attachmentStream.computeContentType() {
            case .image(let pixelSize):
                return pixelSize.compute()
            case .animatedImage(let pixelSize):
                return pixelSize.compute()
            case .audio, .video, .file, .invalid:
                return .zero
            }
        }()
        imagePixelSizeCache.set(result)
        return result
    }

    public var previewDescription: String? { linkPreview.previewDescription }

    public var date: Date? { linkPreview.date }

    public let isGroupInviteLink = false
    public var isCallLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }
}
