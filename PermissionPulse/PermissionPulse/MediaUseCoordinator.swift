import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsUI

@MainActor
final class MediaUseCoordinator {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "media-use-coordinator"
    )

    private let viewModel: AppViewModel
    private let observer: any MediaUseObserver
    private let mediaDataSource: AppViewModel.DataSource
    private var task: Task<Void, Never>?

    init(
        viewModel: AppViewModel,
        observer: any MediaUseObserver = MediaUseObserverCMIO(),
        mediaDataSource: AppViewModel.DataSource = .live
    ) {
        self.viewModel = viewModel
        self.observer = observer
        self.mediaDataSource = mediaDataSource
    }

    func start() {
        guard task == nil else { return }
        viewModel.mediaDataSource = mediaDataSource
        let stream = observer.events()
        task = Task { @MainActor [weak viewModel] in
            for await event in stream {
                guard let viewModel else { return }
                switch event.device {
                case .microphone: viewModel.micInUse = event.inUse
                case .camera:     viewModel.cameraInUse = event.inUse
                }
            }
        }
        Self.logger.debug("MediaUseCoordinator started")
    }

    func stop() async {
        await observer.stop()
        task?.cancel()
        task = nil
    }
}
