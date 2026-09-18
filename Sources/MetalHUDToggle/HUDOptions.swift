import Foundation

/// Groups used only to organize the UI.
enum HUDGroup: String, CaseIterable, Identifiable {
    case system = "Display & system"
    case frames = "Frames & FPS"
    case gpu = "GPU & CPU"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .system: return "display"
        case .frames: return "speedometer"
        case .gpu: return "cpu"
        }
    }
}

/// Values accepted by MTL_HUD_ELEMENTS (comma-separated list).
enum HUDElement: String, CaseIterable, Identifiable {
    // Display & system
    case device, layersize, layerscale, refreshrate, thermal, gamemode, memory
    // Frames & FPS
    case fps, fpsgraph, framenumber, frameinterval, frameintervalgraph, frameintervalhistogram, presentdelay
    // GPU & CPU
    case gputime, gputimeline, metalcpu, shaders, metalfx

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: return "GPU / device"
        case .layersize: return "Layer size"
        case .layerscale: return "Layer scale"
        case .refreshrate: return "Refresh rate"
        case .thermal: return "Thermal state"
        case .gamemode: return "Game Mode"
        case .memory: return "Memory"
        case .fps: return "FPS"
        case .fpsgraph: return "FPS graph"
        case .framenumber: return "Frame number"
        case .frameinterval: return "Frame interval"
        case .frameintervalgraph: return "Frame interval graph"
        case .frameintervalhistogram: return "Frame interval histogram"
        case .presentdelay: return "Present delay"
        case .gputime: return "GPU time"
        case .gputimeline: return "GPU timeline"
        case .metalcpu: return "Metal CPU time"
        case .shaders: return "Shader compilation"
        case .metalfx: return "MetalFX"
        }
    }

    var group: HUDGroup {
        switch self {
        case .device, .layersize, .layerscale, .refreshrate, .thermal, .gamemode, .memory:
            return .system
        case .fps, .fpsgraph, .framenumber, .frameinterval, .frameintervalgraph,
             .frameintervalhistogram, .presentdelay:
            return .frames
        case .gputime, .gputimeline, .metalcpu, .shaders, .metalfx:
            return .gpu
        }
    }

    /// Sensible starting selection.
    static let defaultSelection: Set<HUDElement> = [.device, .fps, .frameinterval, .gputime, .memory]
}

/// Values accepted by MTL_HUD_ALIGNMENT. Declared in row-major order of a 3x3 grid.
enum HUDAlignment: String, CaseIterable, Identifiable {
    case topleft, topcenter, topright
    case centerleft, centered, centerright
    case bottomleft, bottomcenter, bottomright

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topleft: return "Top left"
        case .topcenter: return "Top center"
        case .topright: return "Top right"
        case .centerleft: return "Center left"
        case .centered: return "Center"
        case .centerright: return "Center right"
        case .bottomleft: return "Bottom left"
        case .bottomcenter: return "Bottom center"
        case .bottomright: return "Bottom right"
        }
    }
}
