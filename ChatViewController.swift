/*
MIT License

Copyright (c) 2017-2019 MessageKit

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import UIKit
import Firebase
import FirebaseAuth
import FirebaseFirestore
import MessageKit
import InputBarAccessoryView
import GoogleSignIn
import OneSignal
import SafariServices
import TLPhotoPicker
import Photos

/// A base class for the example controllers
class ChatViewController: MessagesViewController, MessagesDataSource, UIGestureRecognizerDelegate {
    
    // Firebase properties
    let db = Firestore.firestore()
    var reference: CollectionReference?
    var secondReference: CollectionReference?
    var messageListener: ListenerRegistration?
    private var messageCollection: CollectionReference {
        return db.collection("channels").document(channel!.id!).collection("thread")
    }
    
    let user: GIDGoogleUser? = GIDSignIn.sharedInstance().currentUser

    // Cleans up and refreshes the listening process
    deinit {
        messageListener?.remove()
    }
    
    // Channel must be a variable to allow GroupChatVC pass the value to this variable from segue
    var channel: Channel!
    var channelId: String?
    
    // Get the current user
    let currentUser = Auth.auth().currentUser!

    // MessageVC properties
    lazy var messages: [Message] = []
    
    // TLPhotoPicker related
    var selectedAssets = [TLPHAsset]()
    private var isSendingPhoto = false {
        didSet {
            DispatchQueue.main.async {
                self.messageInputBar.leftStackViewItems.forEach { item in
                    //item.isEnabled = !self.isSendingPhoto
                }
            }
        }
    }
    
    // Firebase storage properties
    private let storage = Storage.storage().reference()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    /// The `BasicAudioController` controll the AVAudioPlayer state (play, pause, stop) and udpate audio cell UI accordingly.
    open lazy var audioController = BasicAudioController(messageCollectionView: messagesCollectionView)

    let refreshControl = UIRefreshControl()
    
    let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        messagesCollectionView.messageCellDelegate = self
        setupCollectionView()
        configureMessageCollectionView()
        configureMessageInputBar()
        
        // Change back button destination
        self.navigationItem.title = channel.name
        self.navigationController?.navigationBar.barTintColor = .white
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: makeBackButton())
        
        // Tap to remove keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard (_:)))
        tapGesture.delegate = self
        self.messagesCollectionView.addGestureRecognizer(tapGesture)
        
        if channelId != nil {
            secondReference = db.collection(["channels", (channelId ?? "found_nil"), "thread"].joined(separator: "/"))
            
            messageListener = secondReference?.order(by: "created", descending: true).limit(to: 20).addSnapshotListener { querySnapshot, error in
                guard let snapshot = querySnapshot else {
                    print("Error listening for channel updates: \(error?.localizedDescription ?? "No error")")
                    return
                }
                
                snapshot.documentChanges.forEach { change in
                    self.handleDocumentChange(change)
                }
            }
        } else {
            guard let id = channel.id else {
                navigationController?.popViewController(animated: true)
                return
            }
            
            // Reference point is where the data is stored in Firestore
            reference = db.collection(["channels", id, "thread"].joined(separator: "/"))
            
            // Firestore calls this listener whenever there is a change to the database
            messageListener = reference?.order(by: "created", descending: true).limit(to: 20).addSnapshotListener { querySnapshot, error in
                guard let snapshot = querySnapshot else {
                    print("Error listening for channel updates: \(error?.localizedDescription ?? "No error")")
                    return
                }
                
                snapshot.documentChanges.forEach { change in
                    self.handleDocumentChange(change)
                }
                
                // Post new message notification via OneSignal
                let oneSignalExternalID = "\(self.currentUser.uid)"
                OneSignal.setExternalUserId(oneSignalExternalID)
                print("The external user ID from the chat window is: \(oneSignalExternalID)")
                
                let lastElement = self.messages.last
                print("The last element is: \(String(describing: lastElement)))")
                let content = lastElement?.content
                print("The pushed notification content is: \(content ?? "Hello World")")
                
                OneSignal.postNotification(["contents": ["en": content], "include_external_user_ids": [oneSignalExternalID]])
                
                /*
                 let payload = [
                 "include_external_user_ids": [oneSignalExternalID],
                 "contents": ["en": content],
                 "badge": 1
                 ] as [String : Any]
                 
                 OneSignal.postNotification(payload, onSuccess: { (result) in
                 print("New chat message notification success!")
                 }) { (error) in
                 print("Error posting notification - \(error?.localizedDescription ?? "Error")")
                 }
                 */
            }
        }
        
        // Set custom buttons at input bar
        configure()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // MockSocket.shared.disconnect()
        audioController.stopAnyOngoingPlaying()
    }
    
    // Unwind segue from giphy view controller
    @IBAction func unwindToChatVC(segue: UIStoryboardSegue) {
        let sourceVC = segue.source as! GiphyCollectionViewController
        if let selectedGif = sourceVC.selectedGif {
            // Save gif message
            let text = "\(AppSettings.displayName ?? "Your tribe member") sent a gif"
            let messageDictionary = ["senderID": currentUser.uid, "content": text, "created": Date(), "senderName": user?.profile?.name! ?? "Bonfirer", "path": selectedGif] as [String : Any]
            var messageDocument: DocumentReference?
            messageDocument = messageCollection.addDocument(data: messageDictionary) { error in
                if let error = error {
                    print("Error adding document: \(error)")
                } else {
                    print("Document added with ID: \(messageDocument!.documentID)")
                }
            }
            // Update last message in channel
            let channelDocument = db.collection("channels").document(channel!.id!)
            channelDocument.updateData(["last_message": text])
        }
    }
    
    func loadFirstMessages() {
        /*
        DispatchQueue.global(qos: .userInitiated).async {
            let count = UserDefaults.standard.mockMessagesCount()
            SampleData.shared.getMessages(count: count) { messages in
                DispatchQueue.main.async {
                    self.messageList = messages
                    self.messagesCollectionView.reloadData()
                    self.messagesCollectionView.scrollToBottom()
                }
            }
        }
        */
    }
    
    @objc
    func loadMoreMessages() {
        /*
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            SampleData.shared.getMessages(count: 20) { messages in
                DispatchQueue.main.async {
                    self.messageList.insert(contentsOf: messages, at: 0)
                    self.messagesCollectionView.reloadDataAndKeepOffset()
                    self.refreshControl.endRefreshing()
                }
            }
        }
        */
    }
    
    func makeBackButton() -> UIButton {
        let backButtonImage = UIImage(named: "back")?.withRenderingMode(.alwaysTemplate)
        let backButton = UIButton(type: .custom)
        backButton.setImage(backButtonImage, for: .normal)
        backButton.tintColor = .customBlue
        backButton.setTitle("Back", for: .normal)
        backButton.setTitleColor(.customBlue, for: .normal)
        backButton.addTarget(self, action: #selector(self.navigateToTrackerView), for: .touchUpInside)
        return backButton
    }
    
    @objc func navigateToTrackerView() {
       
        navigationController?.popViewController(animated: true)
    }
    
    func setupCollectionView() {
        guard let bgColor = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout else {
            print("Can't get flowLayout")
            return
        }
        bgColor.collectionView?.backgroundColor = UIColor(red: 234/255, green: 239/255, blue: 244/255, alpha: 1)
    }
    
    func configureMessageCollectionView() {
        
        messagesCollectionView.messagesDataSource = self
        // messagesCollectionView.messageCellDelegate = self
        
        scrollsToBottomOnKeyboardBeginsEditing = true // default false
        maintainPositionOnKeyboardFrameChanged = true // default false
        
        messagesCollectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadMoreMessages), for: .valueChanged)
    }
    
    func configureMessageInputBar() {
        messageInputBar.delegate = self
        messageInputBar.inputTextView.tintColor = .primaryColor
        messageInputBar.sendButton.setTitleColor(.primaryColor, for: .normal)
        messageInputBar.sendButton.setTitleColor(
            UIColor.primaryColor.withAlphaComponent(0.3),
            for: .highlighted
        )
    }
    
    // MARK: - PickerButtonTapped
    
    func pickerButtonTap() {
        let photoPickerViewController = TLPhotosPickerViewController()
        photoPickerViewController.delegate = self
        //var configure = TLPhotosPickerConfigure()
        //configure.nibSet = (nibName: "CustomCell_Instagram", bundle: Bundle.main) // If you want use your custom cell..
        self.present(photoPickerViewController, animated: true, completion: nil)
    }
    
    // Upload image to firebase storage
    private func uploadImage(_ image: UIImage, to channel: Channel, completion: @escaping (URL?) -> Void) {
        guard let channelID = channel.id else {
          completion(nil)
          return
        }
        
        guard let data = image.jpegData(compressionQuality: 0.4) else {//UIImageJPEGRepresentation(image, 0.4) else {
            completion(nil)
            return
        }

        let metaData = StorageMetadata()
        metaData.contentType = "image/jpeg"
        
        let imageName = [UUID().uuidString, String(Date().timeIntervalSince1970)].joined()
        let imageRef = storage.child(channelID).child(imageName)
        
        imageRef.putData(data, metadata: metaData) { (meta, error) in
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
            }

            imageRef.downloadURL(completion: { (url, error) in
                if let urlPath = url {
                    completion(urlPath)
                    
                    print("The URL path from firebase storage is \(urlPath)")
                }
            })
        }
    }
    
    private func sendPhoto(_ image: UIImage) {
        uploadImage(image, to: channel!) { [weak self] url in
            
            guard let `self` = self else {
              return
            }

            // let text = "\(AppSettings.displayName ?? "Your tribe member") sent a photo"

            // When URL to photo is returned, save a new message with that photo URL to the database
            guard let url = url else {
                return
            }
           
            var message = Message(user: self.currentUser, image: image)
            message.downloadURL = url
            
            let imageURL = message.downloadURL
            print("The returned url from image is \(imageURL)")
            
            self.save(message)
            print("The message with the image is \(message)")
            
            self.messagesCollectionView.scrollToBottom()
        }
    }
    
    // MARK: - Helpers
    
    private func downloadImage(at url: URL, completion: @escaping (UIImage?) -> Void) {
        let ref = Storage.storage().reference(forURL: url.absoluteString)
        let megaByte = Int64(1 * 1024 * 1024)
        
        ref.getData(maxSize: megaByte) { data, error in
          guard let imageData = data else {
            completion(nil)
            return
          }
          
          completion(UIImage(data: imageData))
        }
    }
    
    private func makeButton(named: String) -> InputBarButtonItem {
        return InputBarButtonItem()
            .configure {
                $0.spacing = .fixed(10)
                $0.image = UIImage(named: named)?.withRenderingMode(.alwaysTemplate)
                $0.setSize(CGSize(width: 25, height: 25), animated: false)
                $0.tintColor = UIColor(white: 0.8, alpha: 1)
            }.onSelected {
                $0.tintColor = .primaryColor
            }.onDeselected {
                $0.tintColor = UIColor(white: 0.8, alpha: 1)
            }.onTouchUpInside {_ in
                switch named {
                case "image":
                    self.pickerButtonTap()
                    
                case "giphy":
                    print("giphy")

                default:
                    print("Item Tapped")
                }
                
                /*
                let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                let action = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                actionSheet.addAction(action)
                if let popoverPresentationController = actionSheet.popoverPresentationController {
                    popoverPresentationController.sourceView = $0
                    popoverPresentationController.sourceRect = $0.frame
                }
                self.navigationController?.present(actionSheet, animated: true, completion: nil)
                */
        }
    }
    
    // Allow simultaneous recognition with other gestures
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // Dismiss keyboard
    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        self.messageInputBar.inputTextView.resignFirstResponder()
    }
    
    func insertMessage(_ message: Message) {
        guard !messages.contains(message) else {
            return
        }

        messages.append(message)
        messages.sort()
        print(messages.count)
        
        let isLatestMessage = messages.firstIndex(of: message) == (messages.count - 1)
        let shouldScrollToBottom = messagesCollectionView.isAtBottom && isLatestMessage

        messagesCollectionView.reloadData()

        if shouldScrollToBottom {
            DispatchQueue.main.async {
                self.messagesCollectionView.scrollToBottom(animated: true)
            }
        }
        
        /* Reload last section to update header/footer labels and insert a new one
        messages.append(message)
        messagesCollectionView.performBatchUpdates({
            messagesCollectionView.insertSections([messages.count - 1])
            if messages.count >= 2 {
                messagesCollectionView.reloadSections([messages.count - 2])
            }
        }, completion: { [weak self] _ in
            if self?.isLastSectionVisible() == true {
                self?.messagesCollectionView.scrollToBottom(animated: true)
            }
        })
        */
    }
    
    func isLastSectionVisible() -> Bool {
        
        guard !messages.isEmpty else { return false }
        
        let lastIndexPath = IndexPath(item: 0, section: messages.count - 1)
        
        return messagesCollectionView.indexPathsForVisibleItems.contains(lastIndexPath)
    }
    
    func save(_ message: Message) {
        print("Calling save message function")
        reference?.addDocument(data: message.representation) { error in
            if let e = error {
                print("Error sending message: \(e.localizedDescription)")
                return
            }

            print("Message saved")
            self.messagesCollectionView.scrollToBottom()
        }
    }

    // Observe new database changes
    func handleDocumentChange(_ change: DocumentChange) {
        guard var message = Message(document: change.document) else {
          return
        }
        
        switch change.type {
        case .added:
            if let url = message.downloadURL { // cannot detect message.downloadURL
                print("The URL to be inserted into the local array is \(url)")
                
                downloadImage(at: url) { [weak self] image in
                    guard let `self` = self else {
                        return
                    }
                    
                    guard let image = image else {
                        return
                    }
                    
                    message.image = image
                    self.insertMessage(message)
                    // print("The URL to be inserted into the local array is \(url)")
                }
            } else {
                insertMessage(message)
                print("The normal message to be inserted into the local array is \(message)")
            }
            
        default:
            break
        }
    }
    
    // MARK: - MessagesDataSource
    
    func currentSender() -> SenderType {
        return Sender(senderId: currentUser.uid, displayName: AppSettings.displayName)
    }
    
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messages.count
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messages[indexPath.section]
    }
    
    func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        if indexPath.section % 3 == 0 {
            return NSAttributedString(string: MessageKitDateFormatter.shared.string(from: message.sentDate), attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: UIColor.darkGray])
        }
        return nil
    }
    
    func cellBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        
        return NSAttributedString(string: "Read", attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: UIColor.darkGray])
    }
    
    // Customise name of sender right above the message bubble
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let name = message.sender.displayName
        return NSAttributedString(string: name, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1)])
    }
    
    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        
        let dateString = formatter.string(from: message.sentDate)
        return NSAttributedString(string: dateString, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption2)])
    }
    
}

// MARK: - MessageCellDelegate

extension ChatViewController: MessageCellDelegate {
    
    func didTapAvatar(in cell: MessageCollectionViewCell) {
        print("Avatar tapped")
    }
    
    func didTapMessage(in cell: MessageCollectionViewCell) {
        print("Message tapped")
    }
    
    func didTapImage(in cell: MessageCollectionViewCell) {
        print("Image tapped")
    }
    
    func didTapCellTopLabel(in cell: MessageCollectionViewCell) {
        print("Top cell label tapped")
    }
    
    func didTapCellBottomLabel(in cell: MessageCollectionViewCell) {
        print("Bottom cell label tapped")
    }
    
    func didTapMessageTopLabel(in cell: MessageCollectionViewCell) {
        print("Top message label tapped")
    }
    
    func didTapMessageBottomLabel(in cell: MessageCollectionViewCell) {
        print("Bottom label tapped")
    }

    func didTapPlayButton(in cell: AudioMessageCell) {
        guard let indexPath = messagesCollectionView.indexPath(for: cell),
            let message = messagesCollectionView.messagesDataSource?.messageForItem(at: indexPath, in: messagesCollectionView) else {
                print("Failed to identify message when audio cell receive tap gesture")
                return
        }
        guard audioController.state != .stopped else {
            // There is no audio sound playing - prepare to start playing for given audio message
            audioController.playSound(for: message, in: cell)
            return
        }
        if audioController.playingMessage?.messageId == message.messageId {
            // tap occur in the current cell that is playing audio sound
            if audioController.state == .playing {
                audioController.pauseSound(for: message, in: cell)
            } else {
                audioController.resumeSound()
            }
        } else {
            // tap occur in a difference cell that the one is currently playing sound. First stop currently playing and start the sound for given message
            audioController.stopAnyOngoingPlaying()
            audioController.playSound(for: message, in: cell)
        }
    }

    func didStartAudio(in cell: AudioMessageCell) {
        print("Did start playing audio sound")
    }

    func didPauseAudio(in cell: AudioMessageCell) {
        print("Did pause audio sound")
    }

    func didStopAudio(in cell: AudioMessageCell) {
        print("Did stop audio sound")
    }

    func didTapAccessoryView(in cell: MessageCollectionViewCell) {
        print("Accessory view tapped")
    }
    
    func didSelectURL(_ url: URL) {
        let safariController = SFSafariViewController(url: url)
        present(safariController, animated: true, completion: nil)
        print("Link Selected: \(url)")
    }

}

// MARK: - TLPhotoPicker

extension ChatViewController: TLPhotosPickerViewControllerDelegate {
   
    //TLPhotosPickerViewControllerDelegate
    func dismissPhotoPicker(withTLPHAssets: [TLPHAsset]) {
        // use selected order, fullresolution image
        self.selectedAssets = withTLPHAssets
        
        // Resize the image
        let imageManager = PHCachingImageManager()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let size = CGSize(width: 600, height: 600)
        let assets = withTLPHAssets.compactMap{ $0.phAsset }
        for asset in assets {
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { [weak self] image, info in
                guard let image = image else { return }
                //self?.images.append(image)
                self?.sendPhoto(image)
            }
        }
        //self.collectionView.reloadData()
    }
    
    /*
    func dismissPhotoPicker(withPHAssets: [PHAsset]) {
        // if you want to used phasset.
    }
    */
    
    func photoPickerDidCancel() {
        // cancel
    }
    
    func dismissComplete() {
        // picker viewcontroller dismiss completion
    }
    
    /*
    func canSelectAsset(phAsset: PHAsset) -> Bool {
        //Custom Rules & Display
        //You can decide in which case the selection of the cell could be forbidden.
    }
    */
    
    func didExceedMaximumNumberOfSelection(picker: TLPhotosPickerViewController) {
        // exceed max selection
    }
    
    func handleNoAlbumPermissions(picker: TLPhotosPickerViewController) {
        // handle denied albums permissions case
    }
    
    func handleNoCameraPermissions(picker: TLPhotosPickerViewController) {
        // handle denied camera permissions case
    }
}

// MARK: - MessageLabelDelegate

extension ChatViewController: MessageLabelDelegate {
    
    func didSelectAddress(_ addressComponents: [String: String]) {
        print("Address Selected: \(addressComponents)")
    }
    
    func didSelectDate(_ date: Date) {
        print("Date Selected: \(date)")
    }
    
    func didSelectPhoneNumber(_ phoneNumber: String) {
        print("Phone Number Selected: \(phoneNumber)")
    }
    
    func didSelectTransitInformation(_ transitInformation: [String: String]) {
        print("TransitInformation Selected: \(transitInformation)")
    }

    func didSelectHashtag(_ hashtag: String) {
        print("Hashtag selected: \(hashtag)")
    }

    func didSelectMention(_ mention: String) {
        print("Mention selected: \(mention)")
    }

    func didSelectCustom(_ pattern: String, match: String?) {
        print("Custom data detector patter selected: \(pattern)")
    }

}

// MARK: - MessageInputBarDelegate

extension ChatViewController: InputBarAccessoryViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    /*
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // Local variable inserted by Swift 4.2 migrator.
        let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)
        
        picker.dismiss(animated: true, completion: {
            if let pickedImage = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage {
                // self.inputPlugins.forEach { _ = $0.handleInput(of: pickedImage) }
            }
        })
    }
    */

    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        // When use press send button this method is called
        print("Did press end button: \(text)")
        
        let message = Message(user: currentUser, content: text)
    
        // Calling function to insert and save message
        save(message)
        
        // Clearing input field
        inputBar.inputTextView.text = ""
        messagesCollectionView.reloadData()

        // Here we can parse for which substrings were autocompleted
        let attributedText = messageInputBar.inputTextView.attributedText!
        let range = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.autocompleted, in: range, options: []) { (_, range, _) in

            let substring = attributedText.attributedSubstring(from: range)
            let context = substring.attribute(.autocompletedContext, at: 0, effectiveRange: nil)
            print("Autocompleted: `", substring, "` with context: ", context ?? [])
        }

        let components = inputBar.inputTextView.components
        messageInputBar.inputTextView.text = String()
        messageInputBar.invalidatePlugins()

        // Send button activity animation
        messageInputBar.sendButton.startAnimating()
        messageInputBar.inputTextView.placeholder = "Sending..."
        DispatchQueue.global(qos: .default).async {
            // fake send request task
            sleep(1)
            DispatchQueue.main.async { [weak self] in
                self?.messageInputBar.sendButton.stopAnimating()
                self?.messageInputBar.inputTextView.placeholder = "Message"
                // self?.insertMessages(components)
                self?.messagesCollectionView.scrollToBottom(animated: true)
            }
        }
    }
    
    func configure() {
        let items = [
            makeButton(named: "image")
                .onSelected {
                    $0.tintColor = UIColor(red: 15/255, green: 135/255, blue: 255/255, alpha: 1.0)
                    /*
                    let imagePicker = UIImagePickerController()
                    imagePicker.delegate = self
                    imagePicker.sourceType = .photoLibrary
                    (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.present(imagePicker, animated: true, completion: nil)
                    */
            },
            makeButton(named: "giphy").onSelected {
                $0.tintColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
                let giphyVC = UIStoryboard(name: "Secondary", bundle: nil).instantiateViewController(withIdentifier: "GiphyVC") as! UINavigationController
                giphyVC.modalPresentationStyle = .fullScreen
                self.present(giphyVC, animated: true, completion: nil)
            },
            .flexibleSpace
        ]
        items.forEach { $0.tintColor = .lightGray }
        
        // Finally set the items
        messageInputBar.setStackViewItems(items, forStack: .bottom, animated: false)
    }
}

/* Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
    return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
    return input.rawValue
}
*/
