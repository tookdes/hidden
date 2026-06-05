//
//  HyperlinkTextField.swift
//  Hidden Bar
//
//  Created by phucld on 12/19/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation
import Cocoa

@IBDesignable
class HyperlinkTextField: NSTextField {
    
    @IBInspectable var href: String = ""
    
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(self.bounds, cursor: NSCursor.pointingHand)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // TODO:  Fix this and get the hover click to work.
    }
    
    override func mouseDown(with theEvent: NSEvent) {
        guard let url = URL(string: href),
              let scheme = url.scheme,
              ["https", "http", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}

