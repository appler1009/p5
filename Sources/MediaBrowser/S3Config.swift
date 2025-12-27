import Foundation

struct S3Config: Codable {
  var accessKeyId: String = ""
  var secretAccessKey: String = ""
  var region: String = "us-west-2"
  var bucketName: String = ""
  var basePath: String = ""

  var isValid: Bool {
    !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !bucketName.isEmpty
  }
}

extension S3Config {
  static var `default`: S3Config {
    S3Config()
  }
}
