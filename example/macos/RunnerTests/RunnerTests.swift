import Cocoa
import FlutterMacOS
import XCTest

// 如果插件在 Package.swift 中显式设置为 "type: .dynamic"，
// 则需要在 Xcode 中将插件添加为 RunnerTests 的依赖。

@testable import flutter_ar_plus

// 本文件演示插件 Swift 实现的简单单元测试。
//
// XCTest 用法请参阅 https://developer.apple.com/documentation/xctest。

class RunnerTests: XCTestCase {

  func testGetPlatformVersion() {
    let plugin = FlutterArPlusPlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "必须调用结果回调。")
    plugin.handle(call) { result in
      XCTAssertEqual(result as! String,
                     "macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
