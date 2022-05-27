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
       
        var b = CPP_Wrapper().thresholdForMemoryKillOfActiveProcess()
        
        var kb = b / 1024
        var m = kb / 1024
        var g = m / 1024
        debugPrint("--1--")
        debugPrint("\(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
        b = WKWebViewMemoryAppWrapper.thresholdForMemoryKillOfActiveProcess()
        kb = b / 1024
        m = kb / 1024
        g = m / 1024
        
        debugPrint("--2--")
        debugPrint("\(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        debugPrint("didReceiveMemoryWarning")
    }
}
