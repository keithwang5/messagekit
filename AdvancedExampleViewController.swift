//
//  AdvancedExampleViewController.swift
//  Bonfire
//
//  Created by Keith Wang on 5/16/20.
//  Copyright © 2020 Bonfire. All rights reserved.
//

import UIKit
import MapKit
import MessageKit
import InputBarAccessoryView
import Kingfisher
import FirebaseAuth
import FirebaseFirestore

final class DialogueViewController: ChatViewController {
        
    let outgoingAvatarOverlap: CGFloat = 0
    var lastReadTime: Date?
    
    // Firebase users
    var users: [String: Users] = [:]
    var ref: CollectionReference? {
        return db.collection("users")
    }
    var listener: ListenerRegistration?
    
    // Cleans up and refreshes the listening process
    deinit {
        listener?.remove()
    }
    
    override func viewDidLoad() {
        messagesCollectionView = MessagesCollectionView(frame: .zero, collectionViewLayout: CustomMessagesFlowLayout())
        messagesCollectionView.register(CustomCell.self)
        super.viewDidLoad()
        
        updateTitleView(title: "", subtitle: "")
        
        navigationController?.navigationBar.barTintColor = UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)
        
        listener = ref?.addSnapshotListener { querySnapshot, error in
            guard let snapshot = querySnapshot else {
                print("Error listening for channel updates: \(error?.localizedDescription ?? "No error")")
                return
            }
            
            snapshot.documentChanges.forEach { change in
                self.handleDocumentChange(change)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        /*
        MockSocket.shared.connect(with: [SampleData.shared.nathan, SampleData.shared.wu])
            .onTypingStatus { [weak self] in
                self?.setTypingIndicatorViewHidden(false)
            }.onNewMessage { [weak self] message in
                self?.setTypingIndicatorViewHidden(true, performUpdates: {
                    self?.insertMessage(message)
                })
        }
        */
    }
   
    override func configureMessageCollectionView() {
        super.configureMessageCollectionView()
        
        let layout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout
        layout?.sectionInset = UIEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
        
        // Hide the outgoing avatar and adjust the label alignment to line up with the messages
        layout?.setMessageOutgoingAvatarSize(.zero)
        layout?.setMessageOutgoingMessageTopLabelAlignment(LabelAlignment(textAlignment: .right, textInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)))
        layout?.setMessageOutgoingMessageBottomLabelAlignment(LabelAlignment(textAlignment: .right, textInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)))

        // Set outgoing avatar to overlap with the message bubble
        layout?.setMessageIncomingMessageTopLabelAlignment(LabelAlignment(textAlignment: .left, textInsets: UIEdgeInsets(top: 0, left: 50, bottom: outgoingAvatarOverlap, right: 0)))
        layout?.setMessageIncomingAvatarSize(CGSize(width: 40, height: 40))
        layout?.setMessageIncomingMessagePadding(UIEdgeInsets(top: -outgoingAvatarOverlap, left: 0, bottom: outgoingAvatarOverlap, right: 18))
        
        layout?.setMessageIncomingAccessoryViewSize(CGSize(width: 30, height: 30))
        layout?.setMessageIncomingAccessoryViewPadding(HorizontalEdgeInsets(left: 8, right: 0))
        layout?.setMessageIncomingAccessoryViewPosition(.messageBottom)
        layout?.setMessageOutgoingAccessoryViewSize(CGSize(width: 30, height: 30))
        layout?.setMessageOutgoingAccessoryViewPadding(HorizontalEdgeInsets(left: 0, right: 8))

        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
    }
    
    override func configureMessageInputBar() {
        super.configureMessageInputBar()
        
        messageInputBar.isTranslucent = true
        messageInputBar.separatorLine.isHidden = true
        messageInputBar.inputTextView.tintColor = UIColor(red: 50/255, green: 50/255, blue: 50/255, alpha: 1)
        messageInputBar.inputTextView.backgroundColor = UIColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)
        messageInputBar.inputTextView.placeholderTextColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 36)
        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 36)
        messageInputBar.inputTextView.layer.borderColor = UIColor(red: 200/255, green: 200/255, blue: 200/255, alpha: 1).cgColor
        messageInputBar.inputTextView.layer.borderWidth = 1.0
        messageInputBar.inputTextView.layer.cornerRadius = 16.0
        messageInputBar.inputTextView.layer.masksToBounds = true
        messageInputBar.inputTextView.scrollIndicatorInsets = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        configureInputBarItems()
    }

    private func configureInputBarItems() {
        messageInputBar.setRightStackViewWidthConstant(to: 36, animated: false)
        messageInputBar.sendButton.imageView?.backgroundColor = UIColor(white: 0.85, alpha: 1)
        messageInputBar.sendButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        messageInputBar.sendButton.setSize(CGSize(width: 36, height: 36), animated: false)
        messageInputBar.sendButton.image = #imageLiteral(resourceName: "ic_up")
        messageInputBar.sendButton.title = nil
        messageInputBar.sendButton.imageView?.layer.cornerRadius = 16
        messageInputBar.middleContentViewPadding.right = -38
        let charCountButton = InputBarButtonItem()
            .configure {
                $0.title = "0/1000"
                $0.contentHorizontalAlignment = .right
                $0.setTitleColor(UIColor(white: 0.6, alpha: 1), for: .normal)
                $0.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .bold)
                $0.setSize(CGSize(width: 50, height: 25), animated: false)
            }.onTextViewDidChange { (item, textView) in
                item.title = "\(textView.text.count)/1000"
                let isOverLimit = textView.text.count > 1000
                item.inputBarAccessoryView?.shouldManageSendButtonEnabledState = !isOverLimit // Disable automated management when over limit
                if isOverLimit {
                    item.inputBarAccessoryView?.sendButton.isEnabled = false
                }
                let color = isOverLimit ? .red : UIColor(white: 0.6, alpha: 1)
                item.setTitleColor(color, for: .normal)
        }
        let bottomItems = [.flexibleSpace, charCountButton]
        messageInputBar.middleContentViewPadding.bottom = 8
        messageInputBar.setStackViewItems(bottomItems, forStack: .bottom, animated: false)

        // This just adds some more flare
        messageInputBar.sendButton
            .onEnabled { item in
                UIView.animate(withDuration: 0.3, animations: {
                    item.imageView?.backgroundColor = UIColor(red: 255/255, green: 160/255, blue: 0/255, alpha: 1)
                })
            }.onDisabled { item in
                UIView.animate(withDuration: 0.3, animations: {
                    item.imageView?.backgroundColor = UIColor(white: 0.85, alpha: 1)
                })
        }
    }
    
    // MARK: - Helpers
    
    func isTimeLabelVisible(at indexPath: IndexPath) -> Bool {
        return indexPath.section % 3 == 0 && !isPreviousMessageSameSender(at: indexPath)
    }
    
    func isPreviousMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.section - 1 >= 0 else { return false }
        // return messages[indexPath.section].sender == messages[indexPath.section - 1].sender
        return false
    }
    
    func isNextMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.section + 1 < messages.count else { return false }
        // return messages[indexPath.section].sender == messages[indexPath.section + 1].sender
        return false
    }
    
    func setTypingIndicatorViewHidden(_ isHidden: Bool, performUpdates updates: (() -> Void)? = nil) {
        updateTitleView(title: "MessageKit", subtitle: isHidden ? "2 Online" : "Typing...")
        setTypingIndicatorViewHidden(isHidden, animated: true, whilePerforming: updates) { [weak self] success in
            if success, self?.isLastSectionVisible() == true {
                self?.messagesCollectionView.scrollToBottom(animated: true)
            }
        }
    }
    
    // MARK: - UICollectionViewDataSource
    
    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        guard let messagesDataSource = messagesCollectionView.messagesDataSource else {
            fatalError("Ouch. nil data source for messages")
        }

        // Very important to check this when overriding `cellForItemAt`
        // Super method will handle returning the typing indicator cell
        guard !isSectionReservedForTypingIndicator(indexPath.section) else {
            return super.collectionView(collectionView, cellForItemAt: indexPath)
        }

        let message = messagesDataSource.messageForItem(at: indexPath, in: messagesCollectionView)
        if case .custom = message.kind {
            let cell = messagesCollectionView.dequeueReusableCell(CustomCell.self, for: indexPath)
            cell.configure(with: message, at: indexPath, and: messagesCollectionView)
            return cell
        }
        return super.collectionView(collectionView, cellForItemAt: indexPath)
    }

    // MARK: - MessagesDataSource

    override func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        if isTimeLabelVisible(at: indexPath) {
            return NSAttributedString(string: MessageKitDateFormatter.shared.string(from: message.sentDate), attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: UIColor.darkGray])
        }
        return nil
    }
    
    override func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        if !isPreviousMessageSameSender(at: indexPath) {
            let name = message.sender.displayName
            return NSAttributedString(string: name, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1)])
        }
        return nil
    }

    override func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {

        if !isNextMessageSameSender(at: indexPath) && isFromCurrentSender(message: message) {
            return NSAttributedString(string: "Delivered", attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1)])
        }
        return nil
    }

}

// MARK: - MessagesDisplayDelegate

extension DialogueViewController: MessagesDisplayDelegate {

    // MARK: - Text Messages

    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .black : .darkText
    }

    func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedString.Key: Any] {
        switch detector {
        case .hashtag, .mention:
            if isFromCurrentSender(message: message) {
                return [.foregroundColor: UIColor.white]
            } else {
                return [.foregroundColor: UIColor.primaryColor]
            }
        default: return MessageLabel.defaultAttributes
        }
    }

    func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        // return [.url, .address, .phoneNumber, .date, .transitInformation, .mention, .hashtag]
        return [.url]
    }

    // MARK: - All Messages
    
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .primaryColor : UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)
    }

    func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    
        switch message.kind {
        case .photo:
            let configurationClosure = { (containerView: UIImageView) in
                let imageMask = UIImageView()
                imageMask.image = MessageStyle.bubble.image
                imageMask.frame = containerView.bounds
                containerView.mask = imageMask
                containerView.contentMode = .scaleAspectFill
                
                containerView.kf.indicatorType = .activity
                containerView.kf.indicator?.startAnimatingView()
                    
                let m = message as? Message
                print(m)

                guard
                    let message = message as? Message,
                    let url = message.downloadURL
                else {
                    print("Could not convert message into a readable Message format")
                    return
                }

                print("Setting image to \(url.absoluteString)")
            }
            return .custom(configurationClosure)
        default:
            let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
            
            return .bubbleTail(corner, MessageStyle.TailStyle.pointedEdge)
        }
    }
    
    func configureMediaMessageImageView(_ imageView: UIImageView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        switch message.kind {
        case .photo(let photoItem):
            /// if we don't have a url, that means it's simply a pending message
            guard let url = photoItem.url else {
                imageView.kf.indicator?.startAnimatingView()
                return
            }
            
            imageView.kf.indicatorType = .activity
            imageView.kf.setImage(with: url)

        default:
            break
        }
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        /*
        let senderID = message.sender.senderId
        
        if let profileURL = GlobalVariables.users[senderID]?.profileIconURL, profileURL != "" {
            let url = URL(string: profileURL)!
            avatarView.kf.setImage(with: url)
            avatarView.contentMode = .scaleAspectFill
        } else {
            let avatar = Avatar(image: #imageLiteral(resourceName: "artsy-bg"))
            avatarView.set(avatar: avatar)
        }
        */
        
        let avatar = Avatar(image: #imageLiteral(resourceName: "artsy-bg"))
        avatarView.set(avatar: avatar)
        
        avatarView.frame = CGRect(x: avatarView.frame.origin.x, y: avatarView.frame.origin.y, width: 35, height: 35)
    }
    
    func configureAccessoryView(_ accessoryView: UIView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        // Cells are reused, so only add a button here once. For real use you would need to
        // ensure any subviews are removed if not needed
        accessoryView.subviews.forEach { $0.removeFromSuperview() }
        accessoryView.backgroundColor = .clear

        let shouldShow = Int.random(in: 0...10) == 0
        guard shouldShow else { return }

        let button = UIButton(type: .infoLight)
        button.tintColor = .primaryColor
        accessoryView.addSubview(button)
        button.frame = accessoryView.bounds
        button.isUserInteractionEnabled = false // respond to accessoryView tap through `MessageCellDelegate`
        accessoryView.layer.cornerRadius = accessoryView.frame.height / 2
        accessoryView.backgroundColor = UIColor.primaryColor.withAlphaComponent(0.3)
    }
    
    // MARK: - Location Messages
    
    func annotationViewForLocation(message: MessageType, at indexPath: IndexPath, in messageCollectionView: MessagesCollectionView) -> MKAnnotationView? {
        let annotationView = MKAnnotationView(annotation: nil, reuseIdentifier: nil)
        let pinImage = #imageLiteral(resourceName: "ic_map_marker")
        annotationView.image = pinImage
        annotationView.centerOffset = CGPoint(x: 0, y: -pinImage.size.height / 2)
        return annotationView
    }
    
    func animationBlockForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> ((UIImageView) -> Void)? {
        return { view in
            view.layer.transform = CATransform3DMakeScale(2, 2, 2)
            UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
                view.layer.transform = CATransform3DIdentity
            }, completion: nil)
        }
    }
    
    func snapshotOptionsForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LocationMessageSnapshotOptions {
        
        return LocationMessageSnapshotOptions(showsBuildings: true, showsPointsOfInterest: true, span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))
    }

    // MARK: - Audio Messages

    func audioTintColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return self.isFromCurrentSender(message: message) ? .white : .primaryColor
    }

    func configureAudioCell(_ cell: AudioMessageCell, message: MessageType) {
        audioController.configureAudioCell(cell, message: message) // this is needed especily when the cell is reconfigure while is playing sound
    }
    
}

// MARK: - MessagesLayoutDelegate

extension DialogueViewController: MessagesLayoutDelegate {

    func cellTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        if isTimeLabelVisible(at: indexPath) {
            return 18
        }
        return 0
    }
    
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        if isFromCurrentSender(message: message) {
            return !isPreviousMessageSameSender(at: indexPath) ? 20 : 0
        } else {
            return !isPreviousMessageSameSender(at: indexPath) ? (20 + outgoingAvatarOverlap) : 0
        }
    }

    func messageBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return (!isNextMessageSameSender(at: indexPath) && isFromCurrentSender(message: message)) ? 16 : 0
    }
    
    // Add padding to bottom of each message for better readability
    func footerViewSize(for message: MessageType, at indexPath: IndexPath,
                        in messagesCollectionView: MessagesCollectionView) -> CGSize {
        return CGSize(width: 0, height: 40)
    }

}

