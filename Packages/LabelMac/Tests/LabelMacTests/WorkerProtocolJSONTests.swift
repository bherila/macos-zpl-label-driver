import Foundation
import XCTest
@testable import LabelMac

final class WorkerProtocolJSONTests: XCTestCase {
    func testConversionTicketIntegerFieldsRejectRoundedFractions() throws {
        let template = """
        {"schemaVersion":SCHEMA,"pageNumber":PAGE,
         "physicalSize":{"widthMillimeters":10.25,"heightMillimeters":10.5},
         "resolution":{"xDotsPerMillimeter":1,"yDotsPerMillimeter":1},
         "conversion":{"mode":"textAndBarcodeThreshold","cutoff":CUTOFF},
         "placementPolicy":"fit","extraction":{
           "region":{"x":0,"y":0,"width":1,"height":1},
           "expectedSourceRect":{"x":0,"y":0,"width":72,"height":72},"rotation":ROTATION}}
        """
        let fields = [("SCHEMA", "2"), ("PAGE", "1"), ("CUTOFF", "128"), ("ROTATION", "90")]
        for invalid in ["", "SCHEMA", "PAGE", "CUTOFF", "ROTATION"] {
            var json = template
            for (key, value) in fields {
                json = json.replacingOccurrences(of: key, with: value + (key == invalid ? ".00000000000000000000000000000000001" : ".0"))
            }
            if invalid.isEmpty {
                let ticket = try OfflineConversionTicket(jsonData: Data(json.utf8))
                XCTAssertEqual(ticket.physicalSize.width.value, 10.25)
                XCTAssertEqual(ticket.regionRotation, .degrees90)
            } else {
                XCTAssertThrowsError(try OfflineConversionTicket(jsonData: Data(json.utf8)))
            }
        }
    }

    func testEveryProtocolIntegerSiteRejectsFractionBeforeCodable() throws {
        let fraction = "1.00000000000000000000000000000000001"
        let renderResultKeys = [
            "schemaVersion", "widthDots", "heightDots",
            "zplBytes", "previewBytes", "workerMaximumResidentBytes",
        ]
        // Built by appending independently typed elements: one large mixed
        // tuple-array literal exceeded the type checker's time budget.
        var sites: [(WorkerProtocolJSON.Message, String)] = renderResultKeys.map { key in
            (WorkerProtocolJSON.Message.renderResult, "{\"" + key + "\":" + fraction + "}")
        }
        sites.append((.failure, "{\"schemaVersion\":" + fraction + "}"))
        sites.append((.layoutRequest, "{\"schemaVersion\":" + fraction + "}"))
        sites.append((.layoutRequest, "{\"maximumPages\":" + fraction + "}"))
        sites.append((.layoutRequest, "{\"structuralPages\":[1," + fraction + "]}"))
        sites.append((.layoutRequest, "{\"barcodePages\":[1," + fraction + "]}"))
        sites.append((.layoutResult, "{\"schemaVersion\":" + fraction + "}"))
        sites.append((.layoutResult, "{\"pages\":[{\"rotation\":0},{\"rotation\":" + fraction + "}]}"))
        for (message, json) in sites {
            XCTAssertThrowsError(try WorkerProtocolJSON.validate(Data(json.utf8), message: message))
        }
    }

    func testIntegralSpellingsOptionalNullAndFractionalGeometryRemainDistinct() throws {
        for token in ["1", "1.0", "1e0", "100e-2", "9007199254740993", String(Int.max)] {
            let json = "{\"schemaVersion\":\(token),\"workerMaximumResidentBytes\":null}"
            XCTAssertNoThrow(try WorkerProtocolJSON.validate(Data(json.utf8), message: .renderResult))
        }
        let request = Data("{\"schemaVersion\":1,\"maximumPages\":null,\"structuralPages\":[1.0],\"barcodePages\":[2e0]}".utf8)
        XCTAssertNoThrow(try WorkerProtocolJSON.validate(request, message: .layoutRequest))
        let geometry = Data("{\"schemaVersion\":1,\"pages\":[{\"rotation\":90.0,\"width\":1.25,\"height\":2.75}]}".utf8)
        XCTAssertNoThrow(try WorkerProtocolJSON.validate(geometry, message: .layoutResult))
    }

    func testBooleansOverflowAndDuplicateIntegerKeysReject() throws {
        for value in ["true", "\"1\"", "9223372036854775808", "1e999999"] {
            XCTAssertThrowsError(try WorkerProtocolJSON.validate(Data("{\"schemaVersion\":\(value)}".utf8), message: .failure))
        }
        XCTAssertThrowsError(try WorkerProtocolJSON.validate(Data("{\"schemaVersion\":1,\"schemaVersion\":1}".utf8), message: .failure))
    }
}
