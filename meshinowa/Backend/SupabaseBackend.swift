import Foundation
import Supabase

/// ⑮の認証・⑱の同期で使用する接続口。現在の端末内ストアは自動送信しない。
enum SupabaseBackend {
    static func makeClient(bundle: Bundle = .main) throws -> SupabaseClient? {
        guard let configuration = try BackendConfiguration.load(info: bundle.infoDictionary ?? [:]) else { return nil }
        return SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey)
    }
}
