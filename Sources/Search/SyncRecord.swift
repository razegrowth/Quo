import CloudKit
import Foundation

// What a sync record in iCloud looks like, for Quo on the Mac and Quo for
// iPhone alike: the iPhone app (iOS/project.yml) builds this very file, and
// SyncMerge.swift beside it, so the two can't come to disagree about where a
// file is kept or how it is sealed.
//
// One record per device per scope, named "<scope>.<device>", in the zone
// "Sync" of the person's private database. In the clear only where it is
// kept and whose it is; everything it says goes in CloudKit's encrypted
// fields, or, past 700 KB, an asset, which iCloud keeps encrypted too.

enum SyncRecord {
    static let zone = "Sync"
    static let type = "SyncFile"

    static func name(scope: String, device: String) -> String { scope + "." + device }

    /// What a record holds, as the file it was made from.
    static func file(from record: CKRecord) -> SyncFile? {
        guard let scope = record["scope"] as? String else { return nil }
        var data = record.encryptedValues["data"] as? Data
        if data == nil, let asset = record["asset"] as? CKAsset, let url = asset.fileURL { data = try? Data(contentsOf: url) }
        guard let data else { return nil }
        return SyncMerge.decode(data, scope: scope)
    }

    /// The record for a file: where it is kept and whose it is in the
    /// clear, everything it says encrypted. `spare` is the asset's file,
    /// for the caller to remove once it is saved.
    static func record(for file: SyncFile, name: String, zone: CKRecordZone.ID, tag: String, spare: inout URL?) throws -> CKRecord {
        guard let data = SyncMerge.encode(file) else { throw CKError(.invalidArguments) }
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zone))
        record["scope"] = file.scope as NSString
        record["device"] = file.device as NSString
        record["written"] = file.written as NSNumber
        record.encryptedValues["name"] = file.name ?? ""
        // A record holds a megabyte in all; a larger file goes as an asset.
        if data.count < 700_000 {
            record.encryptedValues["data"] = data
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(tag)-sync-\(UUID().uuidString).json")
            try data.write(to: url)
            record["asset"] = CKAsset(fileURL: url)
            spare = url
        }
        return record
    }
}
