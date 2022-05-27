//
//  ViewController.swift
//  WKWebViewMemory
//
//  Created by fuyoufang on 2022/5/26.
//

import UIKit
import WebKit

// https://stackoverflow.com/questions/27565301/wkwebview-goes-blank-after-memory-warning

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
        var b = MemoryPressureWrapper.thresholdForMemoryKillOfActiveProcess()
        var kb = b / 1024
        var m = kb / 1024
        var g = m / 1024
        debugPrint("-- MemoryPressureWrapper.thresholdForMemoryKillOfActiveProcess --")
        debugPrint("\(b)B, \(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
        b = MemoryPressureWrapper.thresholdForMemoryKillOfInactiveProcess()
        kb = b / 1024
        m = kb / 1024
        g = m / 1024
        
        debugPrint("-- MemoryPressureWrapper.thresholdForMemoryKillOfInactiveProcess --")
        debugPrint("\(b)B, \(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
        b = WTFWrapper.thresholdForMemoryKillOfActiveProcess()
        kb = b / 1024
        m = kb / 1024
        g = m / 1024
        
        debugPrint("-- WTFWrapper.thresholdForMemoryKillOfActiveProcess --")
        debugPrint("\(b)B, \(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        debugPrint("didReceiveMemoryWarning")
    }
}
