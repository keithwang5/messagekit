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

// Stores all properties of a message type
struct Message: MessageType {

    let id: String?
    let content: String
    let sentDate: Date
    let sender: Sender
    var kind: MessageKind {
        if let image = image {
            return .photo(image as! MediaItem)
        } else {
            return .text(content)
        }
    }
    var messageId: String {
        return id ?? UUID().uuidString
    }
    
    var image: UIImage? = nil
    var downloadURL: URL? = nil
    
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
        //print(data)
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
        sender = Sender(id: senderID, displayName: senderName)
        
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
        let rep: [String: Any] = [
            "created": sentDate,
            "senderID": sender.id,
            "senderName": sender.displayName,
            "content": content
        ]
        
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
