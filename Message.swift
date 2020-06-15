//
//  Message.swift
//  Bonfire
//
//  Created by Keith Wang on 9/3/19.
//  Copyright © 2019 Bonfire. All rights reserved.
//

import Firebase
import FirebaseFirestore
import MessageKit
import InputBarAccessoryView

private struct PhotoItem: MediaItem {
    
    var url: URL?
    var image: UIImage?
    var placeholderImage: UIImage
    var size: CGSize
    
    init(url: URL) {
        self.url = url
        self.image = nil
        self.size = CGSize(width: 200, height: 200)
        self.placeholderImage = UIImage()
    }
}

// Stores all properties of a message type
struct Message: MessageType {
    
    let id: String?
    let content: String
    let sentDate: Date
    var sender: SenderType
    var messageId: String {
        return id ?? UUID().uuidString
    }
    var image: UIImage? = nil
    var downloadURL: URL? = nil
    var kind: MessageKind {
        if let image = image {
            return .photo(image as! MediaItem)
        } else {
            return .text(content)
        }
    }
    
    init(user: User, content: String) {
        sender = Sender(id: user.uid, displayName: AppSettings.displayName)
        self.content = content
        sentDate = Date()
        id = nil
    }
    
    init(user: User, image: UIImage) {
        sender = Sender(id: user.uid, displayName: AppSettings.displayName)
        self.image = image
        content = ""
        sentDate = Date()
        id = nil
    }
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let sentDate = data["created"] as? Timestamp else {
            return nil
        }
        guard let senderID = data["senderID"] as? String else {
            return nil
        }
        guard let senderName = data["senderName"] as? String else {
            return nil
        }
        
        id = document.documentID
        
        self.sentDate = sentDate.dateValue()
        sender = Sender(senderId: senderID, displayName: senderName)
        
        if let content = data["content"] as? String {
            self.content = content
            downloadURL = nil
        } else if let urlString = data["url"] as? String, let url = URL(string: urlString) {
            downloadURL = url
            self.content = ""
        } else {
            content = ""
        }
    }
    
}

extension Message: DatabaseRepresentation {
    
    var representation: [String : Any] {
        var rep: [String: Any] = [
            "created": sentDate,
            "senderID": sender.senderId,
            "senderName": sender.displayName,
            "content": content
        ]
        
        if let url = downloadURL {
          rep["url"] = url.absoluteString
        } else {
          rep["content"] = content
        }
        
        return rep
    }
    
}

extension Message: Comparable {
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
    
    static func < (lhs: Message, rhs: Message) -> Bool {
        return lhs.sentDate < rhs.sentDate
    }
    
}

