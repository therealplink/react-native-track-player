//
//  AVPlayerWrapper.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 06/03/2018.
//  Copyright © 2018 Jørgen Henrichsen. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

public enum PlaybackEndedReason: String {
    case playedUntilEnd
    case playerStopped
    case skippedToNext
    case skippedToPrevious
    case jumpedToIndex
}

class AVPlayerWrapper: AVPlayerWrapperProtocol {
    var pauseOnEndTimeObservor: Any?;
    
    func cancelPreload(urlString: String) {
        //        print("cancelling preload", urlString);
        guard let asset = self.preloadedAssets[urlString] as? AVAsset else {
            return
        }
        //        print("cancelling preload ", asset);
        asset.cancelLoading();
        self.preloadedAssets[urlString] = nil;
        
    }
    
    func preload(urlString: String) {
        let url =  URL(string: urlString);
        
        //        print("preloading ", urlString);
        
        if let urlUn = url as URL? {
            if(self.preloadedAssets[urlString] == nil){
                
                let asset = AVURLAsset(url:urlUn);
                asset.loadValuesAsynchronously(forKeys: [Constants.assetPlayableKey], completionHandler: nil);
                
                //                let status = asset.statusOfValue(forKey: "playable", error: nil);
                
                //                    let value = asset.value(forKey: "playable");
                //                print("async value ", status.rawValue, status);
                self.preloadedAssets[urlString] = asset;
                
                
            }
            
            //                asset.loadValuesAsynchronously(forKeys: keys, completionHandler: {
            //                    var _: NSError? = nil
            //
            //                    for key in keys {
            //                        let status = asset.statusOfValue(forKey: key, error: nil)
            //                        if status == AVKeyValueStatus.failed {
            //                            return
            //                        }
            ////                        print("status man",status.rawValue)
            //                    }
            
            
            //                });
            
            
        }
        
    }
    
    
    struct Constants {
        static let assetPlayableKey = "playable"
    }
    
    // MARK: - Properties
    public var preloadedAssets = [String: AVAsset]();
    var avPlayer: AVPlayer
    let playerObserver: AVPlayerObserver
    let playerTimeObserver: AVPlayerTimeObserver
    let playerItemNotificationObserver: AVPlayerItemNotificationObserver
    let playerItemObserver: AVPlayerItemObserver
    
    /**
     True if the last call to load(from:playWhenReady) had playWhenReady=true.
     */
    fileprivate var _playWhenReady: Bool = true
    fileprivate var _initialTime: TimeInterval?
    
    fileprivate var _state: AVPlayerWrapperState = AVPlayerWrapperState.idle {
        didSet {
            if oldValue != _state {
                self.delegate?.AVWrapper(didChangeState: _state)
            }
        }
    }
    
    deinit {
        self.playerObserver.stopObserving();

        self.playerItemObserver.stopObservingCurrentItem();
        self.playerItemNotificationObserver.stopObservingCurrentItem();

        playerTimeObserver.unregisterForPeriodicEvents()

        self.playerObserver.delegate = nil
        self.playerTimeObserver.delegate = nil
        self.playerItemNotificationObserver.delegate = nil
        self.playerItemObserver.delegate = nil
    }

    public init() {
        self.avPlayer = AVPlayer()
        self.playerObserver = AVPlayerObserver()
        self.playerObserver.player = avPlayer
        self.playerTimeObserver = AVPlayerTimeObserver(periodicObserverTimeInterval: timeEventFrequency.getTime())
        self.playerTimeObserver.player = avPlayer
        self.playerItemNotificationObserver = AVPlayerItemNotificationObserver()
        self.playerItemObserver = AVPlayerItemObserver()
        
        self.playerObserver.delegate = self
        self.playerTimeObserver.delegate = self
        self.playerItemNotificationObserver.delegate = self
        self.playerItemObserver.delegate = self
        
        playerTimeObserver.registerForPeriodicTimeEvents()
    }
    
    // MARK: - AVPlayerWrapperProtocol
    
    var state: AVPlayerWrapperState {
        return _state
    }
    
    var reasonForWaitingToPlay: AVPlayer.WaitingReason? {
        return avPlayer.reasonForWaitingToPlay
    }
    
    var currentItem: AVPlayerItem? {
        return avPlayer.currentItem
    }
    
    var _pendingAsset: AVAsset? = nil
    
    var automaticallyWaitsToMinimizeStalling: Bool {
        get { return avPlayer.automaticallyWaitsToMinimizeStalling }
        set { avPlayer.automaticallyWaitsToMinimizeStalling = newValue }
    }
    
    var currentTime: TimeInterval {
        let seconds = avPlayer.currentTime().seconds
        return seconds.isNaN ? 0 : seconds
    }
    
    var duration: TimeInterval {
        if let seconds = currentItem?.asset.duration.seconds, !seconds.isNaN {
            return seconds
        }
        else if let seconds = currentItem?.duration.seconds, !seconds.isNaN {
            return seconds
        }
        else if let seconds = currentItem?.loadedTimeRanges.first?.timeRangeValue.duration.seconds,
            !seconds.isNaN {
            return seconds
        }
        return 0.0
    }
    
    var bufferedPosition: TimeInterval {
        return currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? 0
    }
    
    weak var delegate: AVPlayerWrapperDelegate? = nil
    
    var bufferDuration: TimeInterval = 0
    
    var timeEventFrequency: TimeEventFrequency = .everySecond {
        didSet {
            playerTimeObserver.periodicObserverTimeInterval = timeEventFrequency.getTime()
        }
    }
    
    var rate: Float {
        get { return avPlayer.rate }
        set { avPlayer.rate = newValue }
    }
    
    var volume: Float {
        get { return avPlayer.volume }
        set { avPlayer.volume = newValue }
    }
    
    var isMuted: Bool {
        get { return avPlayer.isMuted }
        set { avPlayer.isMuted = newValue }
    }
    
    func play() {
        avPlayer.play()
    }
    
    func pause() {
        avPlayer.pause()
    }
    
    func togglePlaying() {
        switch avPlayer.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            pause()
        case .paused:
            play()
        @unknown default:
            fatalError("Unknown AVPlayer.timeControlStatus")
        }
    }
    
    func stop() {
        pause()
        reset(soft: false)
    }
    
    func seek(to seconds: TimeInterval) {
        avPlayer.seek(to: CMTimeMakeWithSeconds(seconds, preferredTimescale: 10000), toleranceBefore: .zero, toleranceAfter: .zero) { (finished) in
            if let _ = self._initialTime {
                self._initialTime = nil
                if self._playWhenReady {
                    self.play()
                }
            }
            self.delegate?.AVWrapper(seekTo: Int(seconds), didFinish: finished)
        }
        
    }
    
    func pauseOnTime(time: TimeInterval) {
        let end = CMTimeMakeWithSeconds(time, preferredTimescale: 10000);
        let endBoundaryTime: [NSValue] = [end].map({NSValue(time: $0)})
        
        self.clearPauseOnTime();
        
        self.pauseOnEndTimeObservor = avPlayer.addBoundaryTimeObserver(forTimes: endBoundaryTime, queue: nil, using: { [weak self] in
            self?.avPlayer.pause();
        })
        
    }
    
    func clearPauseOnTime() {
        print("clear pause on time ", pauseOnEndTimeObservor);
        guard let pauseOnEndTimeObservor = pauseOnEndTimeObservor else {
            return
        }
        
        avPlayer.removeTimeObserver(pauseOnEndTimeObservor)
        self.pauseOnEndTimeObservor = nil
        
        
    }
    
    func load(from url: URL, playWhenReady: Bool, headers: [String: Any]? = nil) {
        reset(soft: true)
        _playWhenReady = playWhenReady
        
        if currentItem?.status == .failed {
            recreateAVPlayer()
        }
        
        var options: [String: Any] = [:]
        if let headers = headers {
            options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        }
        
        //        print("preloaded asset  ", self.preloadedAssets[url.absoluteString], url.absoluteString)
        
        if(self.preloadedAssets[url.absoluteString] != nil){
            let preloadedAsset = self.preloadedAssets[url.absoluteString];
            let status = preloadedAsset?.statusOfValue(forKey:"playable", error: nil);
            //            print("status before check. ", status?.rawValue)
            
            if(status != .failed){
                //                print("status is not failed.  ", status)
                self._pendingAsset = self.preloadedAssets[url.absoluteString] ?? AVURLAsset(url: url, options: options)
                
                //            print("status of audio asset ", status?.rawValue);
                self.loadAssetIntoPlayer();
                return;
            } else {
                self._pendingAsset = AVURLAsset(url: url, options: options)
                
            }
            
            
            
        } else {
            // Set item
            self._pendingAsset = AVURLAsset(url: url, options: options)
        }
        
        if let pendingAsset = _pendingAsset {
            pendingAsset.loadValuesAsynchronously(forKeys: [Constants.assetPlayableKey], completionHandler: {
                var error: NSError? = nil
                let status = pendingAsset.statusOfValue(forKey: Constants.assetPlayableKey, error: &error)
                
                DispatchQueue.main.async {
                    let isPendingAsset = (self._pendingAsset != nil && pendingAsset.isEqual(self._pendingAsset))
                    switch status {
                    case .loaded:
                        self.loadAssetIntoPlayer();
                        break
                        
                    case .failed:
                        if isPendingAsset {
                            self.delegate?.AVWrapper(failedWithError: error)
                            self._pendingAsset = nil
                        }
                        break
                        
                    case .cancelled:
                        break
                        
                    default:
                        break
                    }
                }
            })
        }
    }
    
    func loadAssetIntoPlayer() {
        if let pendingAsset = _pendingAsset {
            
            let isPendingAsset = (self._pendingAsset != nil && pendingAsset.isEqual(self._pendingAsset))
            
            if isPendingAsset {
                //                print("Loaded  ", pendingAsset);
                let currentItem = AVPlayerItem(asset: pendingAsset, automaticallyLoadedAssetKeys: [Constants.assetPlayableKey])
                currentItem.preferredForwardBufferDuration = self.bufferDuration
                self.avPlayer.replaceCurrentItem(with: currentItem)
                
                // Register for events
                self.playerTimeObserver.registerForBoundaryTimeEvents()
                self.playerObserver.startObserving()
                self.playerItemNotificationObserver.startObserving(item: currentItem)
                self.playerItemObserver.startObserving(item: currentItem)
            }
        }
    }
    
    func load(from url: URL, playWhenReady: Bool, initialTime: TimeInterval?, headers: [String: Any]?) {
        _initialTime = initialTime
        self.pause()
        self.load(from: url, playWhenReady: playWhenReady, headers: headers)
    }
    
    // MARK: - Util
    
    private func reset(soft: Bool) {
        playerItemObserver.stopObservingCurrentItem()
        playerTimeObserver.unregisterForBoundaryTimeEvents()
        playerItemNotificationObserver.stopObservingCurrentItem()
        
        if self._pendingAsset != nil {
            self._pendingAsset?.cancelLoading()
            self._pendingAsset = nil
        }
        
        if !soft {
            avPlayer.replaceCurrentItem(with: nil)
        }
    }
    
    /// Will recreate the AVPlayer instance. Used when the current one fails.
    private func recreateAVPlayer() {
        let player = AVPlayer()
        playerObserver.player = player
        playerTimeObserver.player = player
        playerTimeObserver.registerForPeriodicTimeEvents()
        avPlayer = player
        delegate?.AVWrapperDidRecreateAVPlayer()
    }
    
}

extension AVPlayerWrapper: AVPlayerObserverDelegate {
    
    // MARK: - AVPlayerObserverDelegate
    
    func player(didChangeTimeControlStatus status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused:
            if currentItem == nil {
                _state = .idle
            }
            else {
                self._state = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            self._state = .loading
        case .playing:
            self._state = .playing
        @unknown default:
            break
        }
    }
    
    func player(statusDidChange status: AVPlayer.Status) {
        switch status {
            
        case .readyToPlay:
            self._state = .ready
            
            if let initialTime = _initialTime {
                self.seek(to: initialTime)
            }
            else if _playWhenReady {
                self.play()
            }
            
            break
            
        case .failed:
            self.delegate?.AVWrapper(failedWithError: avPlayer.error)
            break
            
        case .unknown:
            break
        @unknown default:
            break
        }
    }
    
}

extension AVPlayerWrapper: AVPlayerTimeObserverDelegate {
    
    // MARK: - AVPlayerTimeObserverDelegate
    
    func audioDidStart() {
        self._state = .playing
    }
    
    func timeEvent(time: CMTime) {
        self.delegate?.AVWrapper(secondsElapsed: time.seconds)
    }
    
}

extension AVPlayerWrapper: AVPlayerItemNotificationObserverDelegate {
    
    // MARK: - AVPlayerItemNotificationObserverDelegate
    
    func itemDidPlayToEndTime() {
        delegate?.AVWrapperItemDidPlayToEndTime()
    }
    
}

extension AVPlayerWrapper: AVPlayerItemObserverDelegate {
    
    // MARK: - AVPlayerItemObserverDelegate
    
    func item(didUpdateDuration duration: Double) {
        self.delegate?.AVWrapper(didUpdateDuration: duration)
    }
    
}
