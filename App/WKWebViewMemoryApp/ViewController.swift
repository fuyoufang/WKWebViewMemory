//
//  ViewController.swift
//  WKWebViewMemory
//
//  Created by fuyoufang on 2022/5/26.
//

import UIKit
import WebKit

// https://stackoverflow.com/questions/27565301/wkwebview-goes-blank-after-memory-warning

class ViewController: UITableViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
        let b = CPP_Wrapper().thresholdForMemoryKillOfActiveProcess()
        
        let kb = b / 1024
        let m = kb / 1024
        let g = m / 1024
        debugPrint("----")
        debugPrint("\(kb)kB, \(m)M, \(g)G")
        debugPrint("----")
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        debugPrint("didReceiveMemoryWarning")
    }
}
