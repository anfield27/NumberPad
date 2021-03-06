//
//  CanvasViewController.swift
//  NumberPad
//
//  Created by Bridger Maxwell on 12/13/14.
//  Copyright (c) 2014 Bridger Maxwell. All rights reserved.
//

import UIKit
import DigitRecognizerSDK

class CanvasViewController: UIViewController, NumberSlideViewDelegate, NameCanvasDelegate, UIViewControllerTransitioningDelegate {
    
    init(digitRecognizer: DigitRecognizer) {
        self.digitRecognizer = digitRecognizer
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.digitRecognizer = DigitRecognizer()
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.isMultipleTouchEnabled = true
        self.view.isUserInteractionEnabled = true
        self.view.isExclusiveTouch = true
        self.view.backgroundColor = UIColor.backgroundColor()
        
        self.scrollView = UIScrollView(frame: self.view.bounds)
        self.scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.scrollView.isUserInteractionEnabled = false
        self.scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        self.view.addGestureRecognizer(self.scrollView.panGestureRecognizer)
        self.view.insertSubview(self.scrollView, at: 0)
        
        let valuePickerHeight: CGFloat = 85.0
        valuePicker = NumberSlideView(frame: CGRect(x: 0, y:  self.view.bounds.size.height - valuePickerHeight, width:  self.view.bounds.size.width, height: valuePickerHeight))
        valuePicker.delegate = self
        valuePicker.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        self.view.addSubview(valuePicker)
        self.selectedConnectorLabel = nil

        ghostButton = UIButton(type: .custom)
        ghostButton.setTitle("Show Ghosts 👻", for: .normal)
        ghostButton.setTitle("Hide Ghosts 👻", for: .selected)
        ghostButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        ghostButton.setTitleColor(UIColor.blue, for: [])
        ghostButton.isHidden = true
        self.view.addAutoLayoutSubview(subview: ghostButton)
        self.view.addHorizontalConstraints([ghostButton]-6-|)
        self.view.addVerticalConstraints(|-15-[ghostButton])
        ghostButton.addTarget(self, action: #selector(CanvasViewController.ghostButtonTapped), for: .touchUpInside)
    }
    
    var scrollView: UIScrollView!
    var valuePicker: NumberSlideView!
    var ghostButton: UIButton!
    
    var strokeRecognizer: StrokeGestureRecognizer!
    var unprocessedStrokes: [Stroke] = []
    var digitRecognizer: DigitRecognizer
    
    let connectorZPosition: CGFloat = -1
    let constraintZPosition: CGFloat = -2
    let connectionLayersZPosition: CGFloat = -3
    
    // MARK: Managing connectors and constraints
    
    var connectorLabels: [ConnectorLabel] = []
    var connectorToLabel: [Connector: ConnectorLabel] = [:]
    func addConnectorLabel(label: ConnectorLabel, topPriority: Bool, automaticallyConnect: Bool = true) {
        if topPriority {
            connectorLabels.insert(label, at: 0)
        } else {
            connectorLabels.append(label)
        }
        connectorToLabel[label.connector] = label
        label.isSelected = false
        self.scrollView.addSubview(label)
        label.layer.zPosition = connectorZPosition
        updateScrollableSize()
        
        if automaticallyConnect {
            if let (lastConstraint, inputPort) = self.selectedConnectorPort {
                if label.connector.constraints.count == 0 {
                    lastConstraint.connect(inputPort, to: label.connector)
                    self.needsLayout = true
                    self.needsSolving = true
                }
                
                self.selectedConnectorPort = nil
            }
        }
    }
    func moveConnectorToTopPriority(connectorLabel: ConnectorLabel) {
        if let index = connectorLabels.index(of: connectorLabel) {
            if index != 0 {
                connectorLabels.remove(at: index)
                connectorLabels.insert(connectorLabel, at: 0)
            }
        } else {
            print("Tried to move connector to top priority, but couldn't find it!")
        }
    }
    func moveConnectorToBottomPriority(connectorLabel: ConnectorLabel) {
        if let index = connectorLabels.index(of: connectorLabel) {
            if index != connectorLabels.count - 1 {
                connectorLabels.remove(at: index)
                connectorLabels.append(connectorLabel)
            }
        } else {
            print("Tried to move connector to bottom priority, but couldn't find it!")
        }
    }
    func connectorsFromToyInputsToOutputs(_ toy: Toy) -> Set<Connector> {
        // Here we start at a toy's outputs and trace the path to the inputs. We collect all shortest paths
        // betweeen.
        
        // All edges are equal weight, so the shortest path reduces to a breadth-first search
        return connectorsOnPath(from: toy.outputConnectors(), to: toy.inputConnectors(), stopOnFirstPath: false)
    }
    
    func connectorsOnPath(from startConnectors: [Connector], to endConnectors: [Connector], stopOnFirstPath: Bool = true, excluding excludedConnectors: [Connector] = []) -> Set<Connector> {
        var visitedConnectors = Set<Connector>()
        
        struct PathToExplore {
            let path: [Connector]
            // We don't want to backtrack to the same constraint that brought us here. Otherwise, we might
            // go back through a constraint that is directly connected to an endConnector (and thus not in
            // visitedConnectors)
            let constraint: Constraint?
        }
        
        // This is a queue where the oldest is at the back and the newest are at the front
        var connectorsToExplore = [PathToExplore]()
        
        for input in startConnectors {
            visitedConnectors.insert(input)
            connectorsToExplore.insert(PathToExplore(path: [input], constraint: nil), at: 0)
        }
        for excluded in excludedConnectors {
            visitedConnectors.insert(excluded)
        }
        
        var connectorsOnPaths = Set<Connector>()
        while let toExplore = connectorsToExplore.popLast() {
            for constraint in toExplore.path.last!.constraints where constraint !== toExplore.constraint {
                for newConnector in constraint.connectors {
                    if endConnectors.contains(newConnector) {
                        
                        // Add all of this path, except the first element which was the input connector
                        for connector in toExplore.path[1..<toExplore.path.count] {
                            connectorsOnPaths.insert(connector)
                        }
                        if (stopOnFirstPath) {
                            return connectorsOnPaths
                        }
                    } else if case (inserted: true, _) = visitedConnectors.insert(newConnector) {
                        // Remember this path as the shortest path to this connector
                        let newPath = toExplore.path + [newConnector]
                        connectorsToExplore.insert(PathToExplore(path: newPath, constraint: constraint), at: 0)
                    }
                }
            }
        }
        
        return connectorsOnPaths
    }
    
    @discardableResult func remove(connectorLabel label: ConnectorLabel) -> [(ConstraintView, ConnectorPort)] {
        var oldPorts: [(ConstraintView, ConnectorPort)] = []
        if let index = connectorLabels.index(of: label) {
            if label == selectedConnectorLabel {
                selectedConnectorLabel = nil
            }
            connectorLabels.remove(at: index)
            label.removeFromSuperview()
            connectorToLabel[label.connector] = nil
            
            let deleteConnector = label.connector
            for constraintView in self.constraintViews {
                for port in constraintView.connectorPorts() {
                    if port.connector === deleteConnector {
                        constraintView.removeConnector(at: port)
                        oldPorts.append((constraintView, port))
                    }
                }
            }
            self.needsLayout = true
            self.needsSolving = true
        } else {
            print("Cannot remove that label!")
        }
        return oldPorts
    }
    
    var selectedConnectorLabelValueOverride: Double?
    func selectConnectorLabelAndSetToValue(connectorLabel: ConnectorLabel?, value: Double)
    {
        selectedConnectorLabelValueOverride = value
        self.selectedConnectorLabel = connectorLabel
        selectedConnectorLabelValueOverride = nil
    }
    var selectedConnectorLabel: ConnectorLabel? {
        didSet {
            guard selectedConnectorLabel != oldValue else {
                return
            }
            
            if let oldConnectorLabel = oldValue {
                oldConnectorLabel.isSelected = false
            }
            
            if let connectorLabel = selectedConnectorLabel {
                connectorLabel.isSelected = true
                self.selectedConnectorPort = nil
                self.selectedToy = nil
                
                // Here we are careful that if there isn't a value already selected (it was a ?), we don't assign a value. We just put 0 in the picker
                let selectedValue = selectedConnectorLabelValueOverride ?? self.lastValue(for: connectorLabel.connector)
                var valueToDisplay = selectedValue ?? 0.0
                selectedConnectorLabelValueOverride = nil
                if !valueToDisplay.isFinite {
                    valueToDisplay = 0.0
                }
                valuePicker.resetToValue( value: NSDecimalNumber(value: Double(valueToDisplay)), scale: connectorLabel.scale)
                
                // If this is the input of a toy, make sure the outputs are low priority
                for toy in self.toys {
                    if toy.inputConnectors().contains(connectorLabel.connector)  {
                        for connectorToOutput in connectorsFromToyInputsToOutputs(toy) {
                            if let outputLabel = self.connectorToLabel[connectorToOutput] {
                                debugPrint("Moving connector \(outputLabel.valueLabel.text) to bottom")
                                self.moveConnectorToBottomPriority(connectorLabel: outputLabel)
                            }
                        }
                        for output in toy.outputConnectors() {
                            if let outputLabel = self.connectorToLabel[output] {
                                self.moveConnectorToBottomPriority(connectorLabel: outputLabel)
                            }
                        }
                    }
                }
                
                if let selectedValue = selectedValue {
                    updateDisplay(values: [connectorLabel.connector : selectedValue], needsSolving: true)
                } else {
                    updateDisplay(needsSolving: true)
                }
                
                valuePicker.isHidden = false
            } else {
                valuePicker.isHidden = true
                if oldValue != nil {
                    // Solve again, to clear dependent connections
                    updateDisplay(needsSolving: true)
                }
            }
        }
    }
    
    var selectedToy: SelectableToy? {
        didSet {
            guard selectedToy !== oldValue else {
                return
            }
            if let oldToy = oldValue {
                oldToy.selected = false
            }
            
            if let selectedToy = selectedToy {
                selectedToy.selected = true
                self.selectedConnectorPort = nil
                self.selectedConnectorLabel = nil
                
                for input in selectedToy.inputConnectors() {
                    // We want this to be a pretty high priority, because if it is dependent then we can't
                    // ghost
                    if let connectorLabel = self.connectorToLabel[input] {
                        moveConnectorToTopPriority(connectorLabel: connectorLabel)
                    }
                }
                
                var values: [Connector: Double] = [:]
                for output in selectedToy.outputConnectors() {
                    // These will be the highest priority, because they are what the user is actually
                    // moving
                    if let connectorLabel = self.connectorToLabel[output] {
                        moveConnectorToTopPriority(connectorLabel: connectorLabel)
                    }
                    if let selectedValue = self.lastValue(for: output) {
                        values[output] = selectedValue
                    }
                }
                
                // Update the display to show which variables are dependent
                updateDisplay(values: values, needsSolving: true)
            } else {
                // Solve again, to clear dependent connections
                updateDisplay(needsSolving: true)
            }
        }
    }
    
    func deselectEverything() {
        self.selectedConnectorLabel = nil
        self.selectedConnectorPort = nil
        self.selectedToy = nil
    }
    
    var dependentConnectors: [Connector] {
        get {
            var connectors = [Connector]()
            if let selectedConnectorLabel = selectedConnectorLabel {
                connectors.append(selectedConnectorLabel.connector)
            }
            if let selectedToy = selectedToy {
                connectors += selectedToy.outputConnectors()
            }
            return connectors
        }
    }
    
    var constraintViews: [ConstraintView] = []
    func addConstraintView(constraintView: ConstraintView, firstInputPort: ConnectorPort?, secondInputPort: ConnectorPort?, outputPort: ConnectorPort?) {
        constraintViews.append(constraintView)
        self.scrollView.addSubview(constraintView)
        constraintView.layer.zPosition = constraintZPosition
        updateScrollableSize()
        
        if let outputPort = outputPort, let (lastConstraint, inputPort) = self.selectedConnectorPort {
            if connectorToLabel[inputPort.connector] == nil {
                self.connectConstraintViews(firstConstraintView: constraintView, firstConnectorPort: outputPort, secondConstraintView: lastConstraint, secondConnectorPort: inputPort)
            }
        }
        
        if let firstInputPort = firstInputPort, let selectedConnector = self.selectedConnectorLabel {
            constraintView.connect(firstInputPort, to: selectedConnector.connector)
            self.needsLayout = true
            self.needsSolving = true
        }
        if let secondInputPort = secondInputPort {
            self.selectedConnectorPort = (constraintView, secondInputPort)
        } else {
            self.selectedConnectorPort = nil
        }
    }
    var selectedConnectorPort: (ConstraintView: ConstraintView, ConnectorPort: ConnectorPort)? {
        didSet {
            guard selectedConnectorPort != nil || oldValue != nil else {
                return
            }
            
            if let (oldConstraintView, oldConnectorPort) = oldValue {
                oldConstraintView.setConnector(port: oldConnectorPort, isHighlighted: false)
            }
            
            if let (newConstraintView, newConnectorPort) = self.selectedConnectorPort {
                newConstraintView.setConnector(port: newConnectorPort, isHighlighted: true)
                
                self.selectedConnectorLabel = nil
                self.selectedToy = nil
            }
        }
    }
    // This is a conviencence for unhighlighting a connector port that was possibly part of a drag. We only
    // want to do this if it isn't the permanently selected connector. Also, this accepts the parameters as
    // optionals for convenience.
    func unhighlightConnectorPortIfNotSelected(constraintView: ConstraintView?, connectorPort: ConnectorPort?) {
        if let constraintView = constraintView, let connectorPort = connectorPort {
            if selectedConnectorPort?.ConnectorPort !== connectorPort {
                constraintView.setConnector(port: connectorPort, isHighlighted: false)
            }
        }
    }
    
    func removeConstraintView(constraintView: ConstraintView) {
        if let index = constraintViews.index(of: constraintView) {
            constraintViews.remove(at: index)
            constraintView.removeFromSuperview()
            for port in constraintView.connectorPorts() {
                constraintView.removeConnector(at: port)
            }
            if self.selectedConnectorPort?.ConstraintView == constraintView {
                self.selectedConnectorPort = nil
            }
            
            self.needsLayout = true
            self.needsSolving = true
        } else {
            print("Cannot remove that constraint!")
        }
    }
    
    
    var connectionLayers: [CAShapeLayer] = []
    var lastSimulationValues: [Connector: SimulationContext.ResolvedValue]?
    func lastValue(for connector: Connector) -> Double? {
        return self.lastSimulationValues?[connector]?.DoubleValue
    }
    func lastInformant(for connector: Connector) -> (WasDependent: Bool, Informant: Constraint?)? {
        if let lastValue = self.lastSimulationValues?[connector] {
            return (lastValue.WasDependent, lastValue.Informant)
        }
        return nil
    }
    
    // MARK: Gestures
    enum GestureClassification {
        case Stroke
        case MakeConnection
        case Drag
        case Delete
        case OperateToy(SelectableToy, CGPoint)
        case GraphPoke(GraphingToy)
        case GraphPinch(GraphingToy, GraphPinchInfo)
    }
    
    struct GraphPinchInfo {
        let firstTouchID: TouchID
        let firstTouchInitialPoint: CGPoint
        let secondTouchID: TouchID
        let secondTouchInitialPoint: CGPoint
        let initialGraphOffset: CGPoint
        let initialScale: CGFloat
    }
    
    class TouchInfo {
        // The classification can change mid-stroke, so we need to store the initial state for several
        // possible classifications in this class. This data isn't mutually exclusive so it isn't store
        // in the classification enum.
        var connectorLabel: (ConnectorLabel: ConnectorLabel, Offset: CGPoint)?
        var constraintView: (ConstraintView: ConstraintView, Offset: CGPoint, ConnectorPort: ConnectorPort?)?
        var drawConnectionLine: CAShapeLayer?
        var highlightedConnectorPort: (ConstraintView: ConstraintView, ConnectorPort: ConnectorPort)?
        var toy: (Toy: SelectableToy, Offset: CGPoint)?
        var graph: GraphingToy?
        var secondTouchPoint: CGPoint? // Updated with only for two finger gestures, like GraphPinch
        
        let currentStroke = Stroke()
        
        var phase: UITouchPhase = .began
        var classification: GestureClassification?
        
        let initialPoint: CGPoint
        let initialTime: TimeInterval
        init(initialPoint: CGPoint, initialTime: TimeInterval) {
            self.initialPoint = initialPoint
            self.initialTime = initialTime
        }
        
        func pickedUpView() -> (View: UIView, Offset: CGPoint)? {
            if let connectorLabel = self.connectorLabel {
                return (connectorLabel.ConnectorLabel, connectorLabel.Offset)
            } else if let constraintView =  self.constraintView {
                return (constraintView.ConstraintView, constraintView.Offset)
            } else {
                return nil
            }
        }
    }
    
    var touchTracker = TouchTracker()
    var touches: [TouchID: TouchInfo] = [:]
    var processStrokesCounter: Int = 0
    
    let dragDelayTime = 0.2
    let dragMaxDistance: CGFloat = 10
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // We use regular location instead of precise location for hit testing
            let point = touch.location(in: self.scrollView)
            
            let touchInfo = TouchInfo(initialPoint: point, initialTime: touch.timestamp)
            let touchID = touchTracker.id(for: touch)
            
            // Grab all points for this touch, including those between display refreshes (from Pencil esp)
            for coalesced in event?.coalescedTouches(for: touch) ?? [] {
                let point = coalesced.preciseLocation(in: self.scrollView)
                touchInfo.currentStroke.append( point)
            }
            
            if let selectedToy = self.selectableToy(at: point) {
                touchInfo.toy = (selectedToy, selectedToy.center - point)
            }
            if let connectorLabel = self.connectorLabel(at: point) {
                touchInfo.connectorLabel = (connectorLabel, connectorLabel.center - point)
            } else if let (constraintView, connectorPort) = self.connectorPort(at: point) {
                touchInfo.constraintView = (constraintView, constraintView.center - point, connectorPort)
            } else if let constraintView = self.constraintView(at: point) {
                touchInfo.constraintView = (constraintView, constraintView.center - point, nil)
            } else if let graph = self.graph(at: point) {
                touchInfo.graph = graph
                
                if let allTouches = event?.allTouches, allTouches.count == 2 {
                    // This might be a gesture to pinch the graph. If we are the second touch
                    // we just associate this touch with the first touchID
                    for otherTouch in allTouches where otherTouch != touch {
                        let otherTouchID = touchTracker.id(for: otherTouch)
                        guard let otherTouchInfo = self.touches[otherTouchID],
                            otherTouchInfo.graph != nil else {
                                continue
                        }
                        let info = GraphPinchInfo(firstTouchID: otherTouchID, firstTouchInitialPoint: otherTouchInfo.initialPoint, secondTouchID: touchID, secondTouchInitialPoint: point, initialGraphOffset: graph.graphOffset, initialScale: graph.graphScale)
                        changeTouchToClassification(touchInfo: otherTouchInfo, classification: .GraphPinch(graph, info))
                        return
                    }
                }
            }
            self.touches[touchID] = touchInfo
            
            // Test for a long press, to trigger a drag
            if (touchInfo.connectorLabel != nil || touchInfo.constraintView != nil) && touchInfo.toy == nil {
                delay(after: dragDelayTime) {
                    // If this still hasn't been classified as something else (like a connection draw), then it is a move
                    if touchInfo.classification == nil {
                        if touchInfo.phase == .began || touchInfo.phase == .moved {
                            self.changeTouchToClassification(touchInfo: touchInfo, classification: .Drag)
                        }
                    }
                }
            }
            
            if let lastStroke = self.unprocessedStrokes.last, let lastStrokeLastPoint = lastStroke.points.last {
                if lastStrokeLastPoint.distanceTo(point: point) > 150 {
                    // This was far away from the last stroke, so we process that stroke
                    processStrokes()
                }
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let allTouches = event?.allTouches else {
            return
        }
        
        for touch in allTouches {
            let touchID = touchTracker.id(for: touch)
            if let touchInfo = self.touches[touchID] {
                // Grab all points for this touch, including those between display refreshes (from Pencil esp)
                for coalesced in event?.coalescedTouches(for: touch) ?? [] {
                    let point = coalesced.preciseLocation(in: self.scrollView)
                    touchInfo.currentStroke.append( point)
                }
                // We use regular location instead of precise location for hit testing
                let point = touch.location(in: self.scrollView)
                touchInfo.phase = .moved
                
                // Assign a classification, only if one doesn't exist
                if touchInfo.classification == nil {
                    if let (toy, offset) = touchInfo.toy {
                        changeTouchToClassification(touchInfo: touchInfo, classification: .OperateToy(toy, offset))
                    } else if touchInfo.connectorLabel != nil || touchInfo.constraintView?.ConnectorPort != nil {
                        // If we have moved significantly before the long press timer fired, then this is a connection draw
                        if touchInfo.initialPoint.distanceTo(point: point) > dragMaxDistance {
                            changeTouchToClassification(touchInfo: touchInfo, classification: .MakeConnection)
                        }
                        // TODO: Maybe it should be a failed gesture if there was no connectorPort?
                    } else if let graph =  touchInfo.graph {
                        changeTouchToClassification(touchInfo: touchInfo, classification: .GraphPoke(graph))
                    } else if touchInfo.constraintView == nil {
                        // If they weren't pointing at anything, then this is definitely a stroke
                        changeTouchToClassification(touchInfo: touchInfo, classification: .Stroke)
                    }
                }
                
                if let classification = touchInfo.classification {
                    switch classification {
                    case .GraphPinch(_, let pinchInfo):
                        for otherTouch in allTouches {
                            if touchTracker.id(for: otherTouch) == pinchInfo.secondTouchID {
                                touchInfo.secondTouchPoint = otherTouch.location(in: self.scrollView)
                                break
                            }
                        }
                    case .MakeConnection:
                        fallthrough
                    case .Stroke:
                        // See if this was a scribble, which is a delete gesture
                        if digitRecognizer.strokeIsScribble(touchInfo.currentStroke.points) {
                            changeTouchToClassification(touchInfo: touchInfo, classification: .Delete)
                        }
                    default:
                        break
                    }
                    
                    updateGestureForTouch(touchInfo: touchInfo)
                }
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let touchID = touchTracker.id(for: touch)
            if let touchInfo = self.touches[touchID] {
                // Grab all points for this touch, including those between display refreshes (from Pencil esp)
                for coalesced in event?.coalescedTouches(for: touch) ?? [] {
                    let point = coalesced.preciseLocation(in: self.scrollView)
                    touchInfo.currentStroke.append( point)
                }
                // We use regular location instead of precise location for hit testing
                let point = touch.location(in: self.scrollView)
                
                touchInfo.phase = .ended
                
                // See if this was a tap
                var wasTap = false
                if touch.timestamp - touchInfo.initialTime < dragDelayTime && touchInfo.initialPoint.distanceTo(point: point) <= dragMaxDistance {
                    wasTap = true
                    for point in touchInfo.currentStroke.points {
                        // Only if all points were within the threshold was it a tap
                        if touchInfo.initialPoint.distanceTo(point: point) > dragMaxDistance {
                            wasTap = false
                            break
                        }
                    }
                }
                if wasTap {
                    if touchInfo.classification != nil {
                        undoEffectsOfGestureInProgress(touchInfo: touchInfo)
                    }
                    
                    let isDeleteTap = touch.tapCount == 2
                    if !isDeleteTap {
                        // This is a selection tap
                        if let (ghostableToy, simulationContext) = self.ghostToy(at: point) {
                            self.lastSimulationValues = simulationContext // Show the values for this ghost
                            if let selectable = ghostableToy as? SelectableToy {
                                self.selectedToy = selectable
                            }
                            self.updateDisplay(needsSolving: true)
                            
                        } else if let (selectedToy, _) = touchInfo.toy {
                            self.selectedToy = selectedToy
                            
                        } else if let (connectorLabel, _) = touchInfo.connectorLabel {
                            // We delay this by a bit, so that the selection doesn't happen if a double-tap completes and the connector is deleted
                            delay(after: dragDelayTime) {
                                if let _ = self.connectorLabels.index(of: connectorLabel) { // It will be found unless it has been deleted
                                    if self.selectedConnectorLabel != connectorLabel {
                                        self.selectedConnectorLabel = connectorLabel
                                    } else {
                                        self.showNameCanvas()
                                    }
                                }
                            }
                            
                        } else if let connectorPort = touchInfo.constraintView?.ConnectorPort {
                            if self.selectedConnectorPort?.ConnectorPort !== connectorPort {
                                let constraintView = touchInfo.constraintView!.ConstraintView
                                self.selectedConnectorPort = (constraintView, connectorPort)
                            } else {
                                self.selectedConnectorPort = nil
                            }
                            
                        } else if let (connectorLabel, _, _) = self.connectionLine(at: point) {
                            let lastInformant = self.lastInformant(for: connectorLabel.connector)
                            
                            if (lastInformant != nil && lastInformant!.WasDependent) {
                                // Try to make this connector high priority, so it is constant instead of dependent
                                moveConnectorToTopPriority(connectorLabel: connectorLabel)
                            } else {
                                // Lower the priority of this connector and all connectors from the selected
                                // connectors to it. This way, it will become dependent
                                let excluded = self.selectedToy?.inputConnectors() ?? []
                                for connectorOnPath in connectorsOnPath(from: self.dependentConnectors, to: [connectorLabel.connector], excluding: excluded) {
                                    if let label = connectorToLabel[connectorOnPath] {
                                        debugPrint("Moving connector \(label.valueLabel.text) to bottom")
                                        moveConnectorToBottomPriority(connectorLabel: label)
                                    }
                                }
                                moveConnectorToBottomPriority(connectorLabel: connectorLabel)
                            }
                            updateDisplay(needsSolving: true)
                            
                        } else if let graph = self.graph(at: point) {
                            self.updateDisplay(values: graph.valuesForTap(at: point), needsSolving: true)
                            
                        } else {
                            // De-select everything
                            // TODO: What if they were just drawing a point?
                            self.deselectEverything()
                        }
                        
                    } else {
                        // This is a delete tap
                        var deletedSomething = false
                        if let (connectorLabel, _) = touchInfo.connectorLabel {
                            // Delete this connector!
                            if !self.connectorIsForToy(connector: connectorLabel.connector) {
                                remove(connectorLabel: connectorLabel)
                            }
                            deletedSomething = true
                        }
                        if deletedSomething == false {
                            if let (constraintView, _, _) = touchInfo.constraintView {
                                // Delete this constraint!
                                removeConstraintView(constraintView: constraintView)
                                deletedSomething = true
                            }
                        }
                        
                        if deletedSomething {
                            updateDisplay(needsSolving: true, needsLayout: true)
                        }
                    }
                    
                } else if touchInfo.classification != nil {
                    completeGestureForTouch(touchInfo: touchInfo)
                }
                
                self.touches[touchID] = nil
            } else {
                endGraphPinches(withSecondaryTouchID: touchID)
            }
        }
    }
    
    func endGraphPinches(withSecondaryTouchID secondaryTouchID: TouchID) {
        // This touch may have been the secondary touch for a graph pinch
        for (_, touchInfo) in self.touches {
            guard let classification = touchInfo.classification else {
                continue
            }
            switch classification {
            case .GraphPinch(_, let pinchInfo):
                if pinchInfo.secondTouchID == secondaryTouchID {
                    changeTouchToClassification(touchInfo: touchInfo, classification: nil)
                }
            default:
                break
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        guard let touches = touches else { return }
        for touch in touches {
            let touchID = touchTracker.id(for: touch)
            if let touchInfo = self.touches[touchID] {
                undoEffectsOfGestureInProgress(touchInfo: touchInfo)
                touchInfo.phase = .cancelled
                
                self.touches[touchID] = nil
            } else {
                endGraphPinches(withSecondaryTouchID: touchID)
            }
        }
    }
    
    func changeTouchToClassification(touchInfo: TouchInfo, classification: GestureClassification?) {
        if touchInfo.classification != nil {
            undoEffectsOfGestureInProgress(touchInfo: touchInfo)
        }
        
        touchInfo.classification = classification
        
        if let classification = classification {
            switch classification {
            case .Stroke:
                self.processStrokesCounter += 1
                touchInfo.currentStroke.updateLayer()
                touchInfo.currentStroke.layer.strokeColor = UIColor.textColor().cgColor
                self.scrollView.layer.addSublayer(touchInfo.currentStroke.layer)
                
            case .MakeConnection:
                updateDrawConnectionGesture(touchInfo: touchInfo)
                
            case .Drag:
                if let (pickedUpView, _) = touchInfo.pickedUpView() {
                    setViewPickedUp(view: pickedUpView, pickedUp: true)
                    updateDragGesture(touchInfo: touchInfo)
                    
                } else {
                    fatalError("A touchInfo was classified as Drag, but didn't have a connectorLabel or constraintView.")
                }
                
            case .Delete:
                touchInfo.currentStroke.updateLayer()
                touchInfo.currentStroke.layer.strokeColor = UIColor.red.cgColor
                self.scrollView.layer.addSublayer(touchInfo.currentStroke.layer)
                
            case .OperateToy(let toy, let offset):
                updateOperateToyGesture(touchInfo, toy: toy, offset: offset)
                
            case .GraphPoke(let graph):
                self.deselectEverything()
                for output in graph.outputConnectors() {
                    if let connectorLabel = self.connectorToLabel[output] {
                        moveConnectorToBottomPriority(connectorLabel: connectorLabel)
                    }
                }
                updateGraphPokeGesture(touchInfo, graph: graph)
                
            case .GraphPinch(let graph, _):
                graph.isPinching = true
                self.scrollView.panGestureRecognizer.isEnabled = false
                break
            }
        }
    }
    
    func undoEffectsOfGestureInProgress(touchInfo: TouchInfo) {
        if let classification = touchInfo.classification {
            switch classification {
            case .Stroke:
                touchInfo.currentStroke.layer.removeFromSuperlayer()
            case .MakeConnection:
                if let dragLine = touchInfo.drawConnectionLine {
                    dragLine.removeFromSuperlayer()
                }
                unhighlightConnectorPortIfNotSelected(constraintView: touchInfo.constraintView?.ConstraintView, connectorPort: touchInfo.constraintView?.ConnectorPort)
                unhighlightConnectorPortIfNotSelected(constraintView: touchInfo.highlightedConnectorPort?.ConstraintView, connectorPort: touchInfo.highlightedConnectorPort?.ConnectorPort)
            case .Drag:
                if let (pickedUpView, _) = touchInfo.pickedUpView() {
                    setViewPickedUp(view: pickedUpView, pickedUp: false)
                }
            case .Delete:
                touchInfo.currentStroke.layer.removeFromSuperlayer()
            
            case .GraphPinch(let graph, _):
                graph.isPinching = false
                self.updateDisplay(needsSolving: true)
                self.scrollView.panGestureRecognizer.isEnabled = true
            
            case .OperateToy:
                break // Can't undo
            case .GraphPoke:
                break // Can't undo
            }
        }
    }
    
    func updateGestureForTouch(touchInfo: TouchInfo) {
        if let classification = touchInfo.classification {
            
            switch classification {
            case .Stroke:
                touchInfo.currentStroke.updateLayer()
                
            case .MakeConnection:
                updateDrawConnectionGesture(touchInfo: touchInfo)
                
            case .Drag:
                updateDragGesture(touchInfo: touchInfo)
                
            case .Delete:
                touchInfo.currentStroke.updateLayer()
                
            case .OperateToy(let toy, let offset):
                updateOperateToyGesture(touchInfo, toy: toy, offset: offset)
                
            case .GraphPoke(let graph):
                updateGraphPokeGesture(touchInfo, graph: graph)
                
            case .GraphPinch(let graph, let pinchInfo):
                updateGraphPinchGesture(touchInfo, graph: graph, pinchInfo: pinchInfo)
            }
            
        } else {
            fatalError("A touchInfo must have a classification to update the gesture.")
        }
    }
    
    func completeGestureForTouch(touchInfo: TouchInfo) {
        if let classification = touchInfo.classification {
            
            switch classification {
            case .Stroke:
                touchInfo.currentStroke.updateLayer()
                
                let currentCounter = self.processStrokesCounter
                #if arch(i386) || arch(x86_64)
                    //simulator, give more time to draw stroke
                    let delayTime = 0.8
                    #else
                    //device
                    let delayTime = 0.4
                #endif
                delay(after: delayTime) { [weak self] in
                    if let strongself = self {
                        // If we haven't begun a new stroke in the intervening time, then process the old strokes
                        if strongself.processStrokesCounter == currentCounter {
                            strongself.processStrokes()
                        }
                    }
                }
                digitRecognizer.addStrokeToClassificationQueue(stroke: touchInfo.currentStroke.points)
                unprocessedStrokes.append(touchInfo.currentStroke)
                
            case .MakeConnection:
                completeDrawConnectionGesture(touchInfo: touchInfo)
                
            case .Drag:
                if let (pickedUpView, _) = touchInfo.pickedUpView() {
                    updateDragGesture(touchInfo: touchInfo)
                    setViewPickedUp(view: pickedUpView, pickedUp: false)
                    updateScrollableSize()
                    
                } else {
                    fatalError("A touchInfo was classified as Drag, but didn't have a connectorLabel or constraintView.")
                }
                
            case .Delete:
                completeDeleteGesture(touchInfo: touchInfo)
                touchInfo.currentStroke.layer.removeFromSuperlayer()
                
                
            case .GraphPinch(let graph, _):
                graph.isPinching = false
                self.updateDisplay(needsSolving: true)
                self.scrollView.panGestureRecognizer.isEnabled = true
                break
                
            case .OperateToy:
                break // Nothing left to do
            case .GraphPoke:
                break // Nothing left to do
            }
        } else {
            fatalError("A touchInfo must have a classification to complete the gesture.")
        }
    }
    
    func completeDeleteGesture(touchInfo: TouchInfo) {
        // Find all the connectors, constraintViews, and connections that fall under the stroke and remove them
        for point in touchInfo.currentStroke.points {
            if let connectorLabel = self.connectorLabel(at: point) {
                if !self.connectorIsForToy(connector: connectorLabel.connector) {
                    self.remove(connectorLabel: connectorLabel)
                }
            } else if let constraintView = self.constraintView(at: point) {
                self.removeConstraintView(constraintView: constraintView)
            } else if let (_, constraintView, connectorPort) = self.connectionLine(at: point, distanceCutoff: 2.0) {
                constraintView.removeConnector(at: connectorPort)
                self.needsSolving = true
                self.needsLayout = true
            }
        }
        self.updateDisplay()
    }
    
    func updateOperateToyGesture(_ touchInfo: TouchInfo, toy: SelectableToy, offset: CGPoint) {
        if self.selectedToy !== toy {
            self.selectedToy = toy
        }
        let point = touchInfo.currentStroke.points.last!
        let newCenter = point + offset
        let values = toy.valuesForDrag(to: newCenter)
        updateDisplay(values: values, needsSolving: true)
    }
    
    func updateGraphPokeGesture(_ touchInfo: TouchInfo, graph: GraphingToy) {
        let point = touchInfo.currentStroke.points.last!
        let values = graph.valuesForTap(at: point)
        updateDisplay(values: values, needsSolving: true)
    }
    
    func updateGraphPinchGesture(_ touchInfo: TouchInfo, graph: GraphingToy, pinchInfo: GraphPinchInfo) {
        guard let firstTouchPoint = touchInfo.currentStroke.points.last, let secondTouchPoint = touchInfo.secondTouchPoint else {
            fatalError("Can't update pinch gesture without recent touch points")
        }
        
        let oldDistance = pinchInfo.firstTouchInitialPoint.distanceTo(point: pinchInfo.secondTouchInitialPoint)
        let newDistance = firstTouchPoint.distanceTo(point: secondTouchPoint)
        let scaleChange = oldDistance / newDistance
        graph.graphScale = pinchInfo.initialScale * scaleChange
        
        let graphFrame = self.view.convert(graph.frame, to: self.scrollView) // Touch coordinates are in scrollView
        let graphCenter = graphFrame.center()
        
        let oldPinchCenter = (pinchInfo.firstTouchInitialPoint + pinchInfo.secondTouchInitialPoint) / 2
        let newPinchCenter = (firstTouchPoint + secondTouchPoint) / 2
        
        let oldPinchOffsetInGridCoords = (oldPinchCenter - graphCenter) * pinchInfo.initialScale
        let newPinchOffsetInGridCoords = (newPinchCenter - graphCenter) * graph.graphScale
        var offsetChange = oldPinchOffsetInGridCoords - newPinchOffsetInGridCoords
        // Flip the y coordinate
        offsetChange.y *= -1
        
        graph.graphOffset = pinchInfo.initialGraphOffset + offsetChange
        // Re-run the solver to re-render the graph
        self.updateDisplay(needsSolving: true)
    }
    
    func updateDragGesture(touchInfo: TouchInfo) {
        let point = touchInfo.currentStroke.points.last!
        if let (pickedUpView, offset) = touchInfo.pickedUpView() {
            
            let newPoint = point + offset
            pickedUpView.center = newPoint
            updateDisplay(needsLayout: true)
            
        } else {
            fatalError("A touchInfo was classified as Drag, but didn't have a connectorLabel or constraintView.")
        }
    }
    
    func updateDrawConnectionGesture(touchInfo: TouchInfo) {
        let point = touchInfo.currentStroke.points.last!
        
        if let oldDragLine = touchInfo.drawConnectionLine {
            oldDragLine.removeFromSuperlayer()
        }
        unhighlightConnectorPortIfNotSelected(constraintView: touchInfo.highlightedConnectorPort?.ConstraintView, connectorPort: touchInfo.highlightedConnectorPort?.ConnectorPort)
        
        var dragLine: CAShapeLayer!
        if let (connectorLabel, _) = touchInfo.connectorLabel {
            let targetConstraint = connectorPort(at: point)
            let labelPoint = connectorLabel.center
            let dependent = lastInformant(for: connectorLabel.connector)?.WasDependent ?? false
            dragLine = createConnectionLayer(startPoint: labelPoint, endPoint: point, color: targetConstraint?.ConnectorPort.color, isDependent: dependent, arrowHeadPosition: nil)
            
            touchInfo.highlightedConnectorPort = targetConstraint
            if let (constraintView, connectorPort) = targetConstraint {
                constraintView.setConnector(port: connectorPort, isHighlighted: true)
            }
            
        } else if let (constraintView, _, connectorPort) = touchInfo.constraintView {
            let startPoint = self.scrollView.convert(connectorPort!.center, from: constraintView)
            var endPoint = point
            var dependent = false
            if let targetConnector = connectorLabel(at: point) {
                endPoint = targetConnector.center
                dependent = lastInformant(for: targetConnector.connector)?.WasDependent ?? false
                touchInfo.highlightedConnectorPort = nil
            } else {
                let targetConstraint = self.connectorPort(at: point)
                touchInfo.highlightedConnectorPort = targetConstraint
                if let (constraintView, connectorPort) = targetConstraint {
                    constraintView.setConnector(port: connectorPort, isHighlighted: true)
                }
            }
            dragLine = createConnectionLayer(startPoint: startPoint, endPoint: endPoint, color: connectorPort!.color, isDependent: dependent, arrowHeadPosition: nil)
            constraintView.setConnector(port: connectorPort!, isHighlighted: true)
            
        } else {
            fatalError("A touchInfo was classified as MakeConnection, but didn't have a connectorLabel or connectorPort.")
        }
        
        dragLine.zPosition = connectionLayersZPosition
        self.scrollView.layer.addSublayer(dragLine)
        touchInfo.drawConnectionLine = dragLine
    }
    
    func completeDrawConnectionGesture(touchInfo: TouchInfo) {
        let point = touchInfo.currentStroke.points.last!
        
        if let oldDragLine = touchInfo.drawConnectionLine {
            oldDragLine.removeFromSuperlayer()
        }
        unhighlightConnectorPortIfNotSelected(constraintView: touchInfo.constraintView?.ConstraintView, connectorPort: touchInfo.constraintView?.ConnectorPort)
        unhighlightConnectorPortIfNotSelected(constraintView: touchInfo.highlightedConnectorPort?.ConstraintView, connectorPort: touchInfo.highlightedConnectorPort?.ConnectorPort)
        
        var connectionMade = false
        
        if let (connectorLabel, _) = touchInfo.connectorLabel {
            if let (constraintView, connectorPort) = connectorPort(at: point) {
                self.connect(connectorLabel: connectorLabel, constraintView: constraintView, connectorPort: connectorPort)
                connectionMade = true
            } else if let destinationConnectorLabel = self.connectorLabel(at: point), destinationConnectorLabel != connectorLabel {
                // Try to combine these connector labels
                if connectorIsForToy(connector: destinationConnectorLabel.connector) {
                    if connectorIsForToy(connector: connectorLabel.connector) {
                        // We can't combine these because they are both for toys
                    } else {
                        combineConnectors(bigConnectorLabel: destinationConnectorLabel, connectorLabelToDelete: connectorLabel)
                        connectionMade = true
                    }
                } else {
                    combineConnectors(bigConnectorLabel: connectorLabel, connectorLabelToDelete: destinationConnectorLabel)
                    connectionMade = true
                }
            }
            
        } else if let (constraintView, _, connectorPort) = touchInfo.constraintView {
            if let connectorLabel = connectorLabel(at: point) {
                self.connect(connectorLabel: connectorLabel, constraintView: constraintView, connectorPort: connectorPort!)
                connectionMade = true
                
            } else if let (secondConstraintView, secondConnectorPort) = self.connectorPort(at: point) {
                self.connectConstraintViews(firstConstraintView: constraintView, firstConnectorPort: connectorPort!, secondConstraintView: secondConstraintView, secondConnectorPort: secondConnectorPort)
                
                connectionMade = true
            }
            
        } else {
            fatalError("A touchInfo was classified as MakeConnection, but didn't have a connectorLabel or connectorPort.")
        }
        
        if connectionMade {
            self.updateDisplay()
        }
    }
    
    func setViewPickedUp(view: UIView, pickedUp: Bool) {
        if pickedUp {
            // Add some styles to make it look picked up
            UIView.animate(withDuration: 0.2) {
                view.layer.shadowColor = UIColor.darkGray.cgColor
                view.layer.shadowOpacity = 0.4
                view.layer.shadowRadius = 10
                view.layer.shadowOffset = CGSize(width: 5, height: 5)
            }
        } else {
            // Remove the picked up styles
            UIView.animate(withDuration: 0.2) {
                view.layer.shadowColor = nil
                view.layer.shadowOpacity = 0
            }
        }
    }
    
    func combineConnectors(bigConnectorLabel: ConnectorLabel, connectorLabelToDelete: ConnectorLabel) {
        if bigConnectorLabel == connectorLabelToDelete {
            return
        }
        
        // We just delete connectorLabelToDelete, but wire up all connections to bigConnectorLabel
        
        let oldPorts = remove(connectorLabel: connectorLabelToDelete)
        for (constraintView, port) in oldPorts {
            connect(connectorLabel: bigConnectorLabel, constraintView: constraintView, connectorPort: port)
        }
    }
    
    func connect(connectorLabel: ConnectorLabel, constraintView: ConstraintView, connectorPort: ConnectorPort) {
        for connectorPort in constraintView.connectorPorts() {
            if connectorPort.connector === connectorLabel.connector {
                // This connector is already hooked up to this constraintView. The user is probably trying to change the connection, so we remove the old one
                constraintView.removeConnector(at: connectorPort)
            }
        }
        
        constraintView.connect(connectorPort, to: connectorLabel.connector)
        self.needsSolving = true
        self.needsLayout = true
    }
    
    @discardableResult func connectConstraintViews(firstConstraintView: ConstraintView, firstConnectorPort: ConnectorPort, secondConstraintView: ConstraintView, secondConnectorPort: ConnectorPort) -> ConnectorLabel {
        // We are dragging from one constraint directly to another constraint. To accomodate, we create a connector in-between and make two connections
        let midPoint = (firstConstraintView.center + secondConstraintView.center) / 2.0
        
        let newConnector = Connector()
        let newLabel = ConnectorLabel(connector: newConnector)
        newLabel.sizeToFit()
        newLabel.center = midPoint
        self.addConnectorLabel(label: newLabel, topPriority: false, automaticallyConnect: false)
        
        firstConstraintView.connect(firstConnectorPort, to: newConnector)
        secondConstraintView.connect(secondConnectorPort, to: newConnector)
        self.needsSolving = true
        self.needsLayout = true
        
        return newLabel
    }
    
    func connectorLabel(at point: CGPoint) -> ConnectorLabel? {
        for label in connectorLabels {
            if label.frame.contains(point) {
                return label
            }
        }
        return nil
    }
    
    func constraintView(at point: CGPoint) -> ConstraintView? {
        for view in constraintViews {
            if view.frame.contains(point) {
                return view
            }
        }
        return nil
    }
    
    func graph(at point: CGPoint) -> GraphingToy? {
        for toy in toys {
            if let toy = toy as? GraphingToy {
                let toyFrame = self.view.convert(toy.frame, to: self.scrollView)
                if toyFrame.contains(point) {
                    return toy
                }
            }
        }
        return nil
    }
    
    func connectorPort(at location: CGPoint) -> (ConstraintView: ConstraintView, ConnectorPort: ConnectorPort)? {
        for constraintView in constraintViews {
            let point = constraintView.convert(location, from: self.scrollView)
            if let port = constraintView.connectorPortForDrag(at: point, connectorIsVisible: { self.connectorToLabel[$0] != nil}) {
                return (constraintView, port)
            }
        }
        return nil
    }
    
    func connectionLine(at point: CGPoint, distanceCutoff: CGFloat = 12.0) -> (ConnectorLabel: ConnectorLabel, ConstraintView: ConstraintView, ConnectorPort: ConnectorPort)? {
        // This is a hit-test to see if the user has tapped on a line between a connector and a connectorPort.
        let squaredDistanceCutoff = distanceCutoff * distanceCutoff
        
        var minSquaredDistance: CGFloat?
        var minMatch: (ConnectorLabel, ConstraintView, ConnectorPort)?
        for constraintView in constraintViews {
            for connectorPort in constraintView.connectorPorts() {
                if let connectorLabel = connectorToLabel[connectorPort.connector] {
                    let connectorPoint = self.scrollView.convert(connectorPort.center, from: constraintView)
                    let labelPoint = connectorLabel.center
                    
                    let squaredDistance = shortestDistanceSquaredToLineSegmentFromPoint(segmentStart: connectorPoint, segmentEnd: labelPoint, testPoint: point)
                    if squaredDistance < squaredDistanceCutoff {
                        if minSquaredDistance == nil || squaredDistance < minSquaredDistance! {
                            print("Found elligible distance of \(sqrt(squaredDistance))")
                            minMatch = (connectorLabel, constraintView, connectorPort)
                            minSquaredDistance = squaredDistance
                        }
                    }
                }
            }
        }
        
        return minMatch
    }
    
    func selectableToy(at point: CGPoint) -> SelectableToy? {
        for toy in toys {
            if let selectable = toy as? SelectableToy {
                if selectable.contains(point) {
                    return selectable
                }
            }
        }
        return nil
    }
    
    func ghostToy(at point: CGPoint) -> (GhostableToy, ResolvedValues)? {
        for toy in self.toys {
            if let toy = toy as? GhostableToy {
                guard !toy.ghostsHidden else {
                    continue
                }
                if let resolvedValues = toy.ghostState(at: point) {
                    return (toy, resolvedValues)
                }
            }
        }
        return nil
    }

    override func viewWillAppear(_ animated: Bool) {
        for stroke in self.unprocessedStrokes {
            stroke.layer.removeFromSuperlayer()
        }
        self.digitRecognizer.clearClassificationQueue()
    }
    
    func processStrokes() {
        // Find the bounding rect of all of the strokes
        var topLeft: CGPoint?
        var bottomRight: CGPoint?
        for stroke in self.unprocessedStrokes {
            for point in stroke.points {
                if let capturedTopLeft = topLeft {
                    topLeft = CGPoint(x: min(capturedTopLeft.x, point.x), y: min(capturedTopLeft.y, point.y));
                } else {
                    topLeft = point
                }
                if let capturedBottomRight = bottomRight {
                    bottomRight = CGPoint(x: max(capturedBottomRight.x, point.x), y: max(capturedBottomRight.y, point.y));
                } else {
                    bottomRight = point
                }
            }
            stroke.layer.removeFromSuperlayer()
        }
        let strokeCount = self.unprocessedStrokes.count

        let classifiedLabels = self.digitRecognizer.recognizeStrokesInQueue()

        self.unprocessedStrokes.removeAll(keepingCapacity: false)
        self.digitRecognizer.clearClassificationQueue()

        if let classifiedLabels = classifiedLabels {

            // Figure out where to put the new component
            var centerPoint = self.scrollView.convert(self.view.center, from: self.view)
            if let topLeft = topLeft {
                if let bottomRight = bottomRight {
                    centerPoint = CGPoint(x: (topLeft.x + bottomRight.x) / 2.0, y: (topLeft.y + bottomRight.y) / 2.0)
                }
            }

            var combinedLabels = classifiedLabels.reduce("", +)
            var isPercent = false
            if classifiedLabels.count > 1 && combinedLabels.hasSuffix("/") {
                combinedLabels = combinedLabels.substring(to: combinedLabels.index(before: combinedLabels.endIndex))
                isPercent = true
            }
            var writtenValue: Double?
            if let writtenNumber = Int(combinedLabels) {
                writtenValue = Double(writtenNumber)
            } else if combinedLabels == "e" {
                writtenValue = Double(M_E)
            }
            if writtenValue != nil && isPercent {
                writtenValue = writtenValue! / 100.0
            }

            if combinedLabels == "?" {
                let newConnector = Connector()
                let newLabel = ConnectorLabel(connector: newConnector)
                newLabel.sizeToFit()
                newLabel.center = centerPoint

                self.addConnectorLabel(label: newLabel, topPriority: false)
                self.selectedConnectorLabel = newLabel

            } else if combinedLabels == "x" || combinedLabels == "/" {
                // We recognized a multiply or divide!
                let newMultiplier = Multiplier()
                let newView = MultiplierView(multiplier: newMultiplier)
                newView.layout(withConnectorPositions: [:])
                newView.center = centerPoint
                let inputs = newView.inputConnectorPorts()
                let outputs = newView.outputConnectorPorts()
                if combinedLabels == "x" {
                    self.addConstraintView(constraintView: newView, firstInputPort: inputs[0], secondInputPort: inputs[1], outputPort: outputs[0])
                } else if combinedLabels == "/" {
                    newView.showOperatorFor(output: inputs[0])
                    self.addConstraintView(constraintView: newView, firstInputPort: outputs[0], secondInputPort: inputs[0], outputPort: inputs[1])
                } else {
                    self.addConstraintView(constraintView: newView, firstInputPort: nil, secondInputPort: nil, outputPort: nil)
                }

            } else if combinedLabels == "+" || combinedLabels == "-" {
                // We recognized an add or subtract!
                let newAdder = Adder()
                let newView = AdderView(adder: newAdder)
                newView.layout(withConnectorPositions: [:])
                newView.center = centerPoint
                let inputs = newView.inputConnectorPorts()
                let outputs = newView.outputConnectorPorts()
                if combinedLabels == "+" {
                    let inputs = newView.inputConnectorPorts()
                    self.addConstraintView(constraintView: newView, firstInputPort: inputs[0], secondInputPort: inputs[1], outputPort: outputs[0])
                } else if combinedLabels == "-" {
                    newView.showOperatorFor(output: inputs[0])
                    self.addConstraintView(constraintView: newView, firstInputPort: outputs[0], secondInputPort: inputs[0], outputPort: inputs[1])
                } else {
                    self.addConstraintView(constraintView: newView, firstInputPort: nil, secondInputPort: nil, outputPort: nil)
                }

            } else if combinedLabels == "^" {
                let newExponent = Exponent()
                let newView = ExponentView(exponent: newExponent)
                newView.layout(withConnectorPositions: [:])
                newView.center = centerPoint

                self.addConstraintView(constraintView: newView, firstInputPort: newView.basePort, secondInputPort: newView.exponentPort, outputPort: newView.resultPort)

            } else if let writtenValue = writtenValue {
                // We recognized a number!
                let newConnector = Connector()
                let newLabel = ConnectorLabel(connector: newConnector)
                newLabel.sizeToFit()
                newLabel.center = centerPoint
                newLabel.isPercent = isPercent

                let scale: Int16
                if isPercent {
                    scale = -3
                } else if combinedLabels == "e" {
                    scale = -4
                } else {
                    scale = self.defaultScaleForNewValue(value: writtenValue)
                }
                newLabel.scale = scale

                self.addConnectorLabel(label: newLabel, topPriority: true)
                self.selectConnectorLabelAndSetToValue(connectorLabel: newLabel, value: writtenValue)

            } else {
                print("Unable to parse written text: \(combinedLabels)")
            }
            self.updateDisplay();
        } else {
            print("Unable to recognize all \(strokeCount) strokes")
        }
    }

    func defaultScaleForNewValue(value: Double) -> Int16 {
        if abs(value) < 3 {
            return -2
        } else if abs(value) >= 1000 {
            return 2
        } else if abs(value) >= 100 {
            return 1
        } else {
            return -1
        }
    }

    func numberSlideView(numberSlideView _: NumberSlideView, didSelectNewValue newValue: NSDecimalNumber, scale: Int16) {
        if let selectedConnectorLabel = self.selectedConnectorLabel {
            selectedConnectorLabel.scale = scale
            self.updateDisplay(values: [selectedConnectorLabel.connector : newValue.doubleValue], needsSolving: true, selectNewConnectorLabel: false)
        }
    }

    func numberSlideView(numberSlideView _: NumberSlideView, didSelectNewScale scale: Int16) {
        if let selectedConnectorLabel = self.selectedConnectorLabel {
            selectedConnectorLabel.scale = scale
            selectedConnectorLabel.displayValue(value: lastValue(for: selectedConnectorLabel.connector))
        }
    }
    
    var needsLayout = false
    var needsRebuildConnectionLayers = false
    var needsSolving = false
    
    func updateDisplay(values: [Connector: Double] = [:], needsSolving: Bool = false, needsLayout: Bool = false, selectNewConnectorLabel: Bool = true)
    {
        // See how these variables are used at the end of this function, after the internal definitions
        self.needsLayout = self.needsLayout || needsLayout
        self.needsSolving = self.needsSolving || needsSolving || values.count > 0
        
        func rebuildAllConnectionLayers() {
            for oldLayer in self.connectionLayers {
                oldLayer.removeFromSuperlayer()
            }
            self.connectionLayers.removeAll(keepingCapacity: true)
            
            for constraintView in self.constraintViews {
                for connectorPort in constraintView.connectorPorts() {
                    if let connectorLabel = self.connectorToLabel[connectorPort.connector] {
                        let constraintPoint = self.scrollView.convert(connectorPort.center, from: constraintView)
                        let labelPoint = connectorLabel.center
                        
                        let lastInformant = self.lastInformant(for: connectorLabel.connector)
                        let dependent = lastInformant?.WasDependent ?? false
                        
                        let startPoint: CGPoint
                        let endPoint: CGPoint
                        var arrowHeadPosition: CGFloat = 0.33
                        // If this contraintView was the informant, then the arrow goes from the constraint
                        // to the connector. Otherwise, it goes from the connector to the constraint
                        if lastInformant?.Informant == constraintView.constraint {
                            startPoint = constraintPoint
                            endPoint = labelPoint
                        } else {
                            startPoint = labelPoint
                            endPoint = constraintPoint
                            arrowHeadPosition = 1 - arrowHeadPosition
                        }
                        // Don't draw the arrow head if there was no informant
                        let drawArrowHead: CGFloat? = lastInformant == nil ? nil : arrowHeadPosition;
                        
                        let connectionLayer = self.createConnectionLayer(startPoint: startPoint, endPoint: endPoint, color: connectorPort.color, isDependent: dependent, arrowHeadPosition: drawArrowHead)
                        
                        self.connectionLayers.append(connectionLayer)
                        connectionLayer.zPosition = self.connectionLayersZPosition
                        self.scrollView.layer.addSublayer(connectionLayer)
                    }
                }
            }
            self.needsRebuildConnectionLayers = false
        }
        
        func layoutConstraintViews() {
            var connectorPositions: [Connector: CGPoint] = [:]
            for connectorLabel in self.connectorLabels {
                connectorPositions[connectorLabel.connector] = connectorLabel.center
            }
            for constraintView in self.constraintViews {
                constraintView.layout(withConnectorPositions: connectorPositions)
            }
            self.needsLayout = false
            self.needsRebuildConnectionLayers = true
        }
        
        func runSolver() {
            let lastSimulationValues = self.lastSimulationValues
            
            var connectorToSelect: ConnectorLabel?
            let simulationContext = SimulationContext(connectorResolvedCallback: { (connector, resolvedValue) -> Void in
                if self.connectorToLabel[connector] == nil {
                    if let constraint = resolvedValue.Informant {
                        // This happens when a constraint makes a connector on it's own. For example, if you set two inputs on a multiplier then it will resolve the output automatically. We need to add a view for it and display it
                        
                        // We need to find the constraintView and the connectorPort this belongs to
                        var connectTo: (constraintView: ConstraintView, connectorPort: ConnectorPort)!
                        for possibleView in self.constraintViews {
                            if possibleView.constraint == constraint {
                                for possiblePort in possibleView.connectorPorts() {
                                    if possiblePort.connector == connector {
                                        connectTo = (possibleView, possiblePort)
                                        break
                                    }
                                }
                                break
                            }
                        }
                        if connectTo == nil {
                            print("Unable to find constraint view for newly resolved connector! \(connector), \(resolvedValue), \(constraint)")
                            return
                        }
                        
                        let newLabel = ConnectorLabel(connector: connector)
                        newLabel.scale = self.defaultScaleForNewValue(value: resolvedValue.DoubleValue)
                        newLabel.sizeToFit()
                        
                        // Find the positions of the existing connectorLabels on this constraint
                        var connectorPositions: [Connector: CGPoint] = [:]
                        for existingConnector in connectTo.constraintView.connectorPorts().map({$0.connector}) {
                             if let existingLabel = self.connectorToLabel[existingConnector] {
                                connectorPositions[existingConnector] = existingLabel.center
                            }
                        }
                        
                        let angle = connectTo.constraintView.idealAngleForNewConnectorLabel(connector: connector, positions: connectorPositions)
                        let distance: CGFloat = 70 + max(connectTo.constraintView.bounds.width, connectTo.constraintView.bounds.height)
                        let newDisplacement = CGPoint(x: cos(angle), y: sin(angle)) * distance
                        
                        // Make sure the new point is somewhat on the screen
                        var newPoint = connectTo.constraintView.frame.center() + newDisplacement
                        let minMargin: CGFloat = 10
                        newPoint.x = max(newPoint.x, minMargin)
                        newPoint.x = min(newPoint.x, self.scrollView.contentSize.width - minMargin)
                        newPoint.y = max(newPoint.y, minMargin)
                        
                        newLabel.center = newPoint
                        newLabel.alpha = 0
                        self.addConnectorLabel(label: newLabel, topPriority: false, automaticallyConnect: false)
                        UIView.animate(withDuration: 0.5) {
                            newLabel.alpha = 1.0
                        }
                        connectorToSelect = newLabel
                        self.needsLayout = true
                    }
                }
                
                if let label = self.connectorToLabel[connector] {
                    label.displayValue(value: resolvedValue.DoubleValue)
                    connector.debugValue = resolvedValue.DoubleValue
                }
                if let lastValue = lastSimulationValues?[connector] {
                    if (lastValue.WasDependent != resolvedValue.WasDependent || lastValue.Informant != resolvedValue.Informant) {
                        self.needsRebuildConnectionLayers = true
                    }
                } else {
                    self.needsRebuildConnectionLayers = true
                }
                }, connectorConflictCallback: { (connector, resolvedValue) -> Void in
                    if let label = self.connectorToLabel[connector] {
                        label.hasError = true
                    }
            })
            
            // Reset all error states
            for label in self.connectorLabels {
                label.hasError = false
            }
            
            let dependentConnectors = self.dependentConnectors
            
            // These are the first priority
            for (connector, value) in values {
                let dependent = dependentConnectors.contains(connector)
                simulationContext.setConnectorValue(connector: connector, value: (DoubleValue: value, Expression: constantExpression(number: value), WasDependent: dependent, Informant: nil))
            }
            
            func resolveToLastValue(_ connector: Connector) {
                let dependent = dependentConnectors.contains(connector)
                
                // If we haven't already resolved this connector, then set it to the value from the last simulation
                if simulationContext.connectorValues[connector] == nil {
                    if let lastValue = lastSimulationValues?[connector]?.DoubleValue {
                        simulationContext.setConnectorValue(connector: connector, value: (DoubleValue: lastValue, Expression: constantExpression(number: lastValue), WasDependent: dependent, Informant: nil))
                    }
                }
            }
            
            for connector in dependentConnectors {
                resolveToLastValue(connector)
            }
            
            // We loop through connectorLabels like this, because it can mutate during the simulation, if a constraint "resolves a port"
            var index = 0
            while index < self.connectorLabels.count {
                resolveToLastValue(self.connectorLabels[index].connector)
                index += 1
            }
            
            // Update the labels that still don't have a value
            for label in self.connectorLabels {
                if simulationContext.connectorValues[label.connector] == nil {
                    label.displayValue(value: nil)
                }
            }
            
            constraintLoop: for constraintView in self.constraintViews {
                let constraint = constraintView.constraint
                for connectorPort in constraintView.connectorPorts() {
                    let connector = connectorPort.connector
                    if simulationContext.connectorValues[connector]?.Informant == constraint {
                        // Show the label for which operator was used to calculate the result
                        constraintView.showOperatorFor(output: connectorPort)
                        continue constraintLoop
                    }
                }
            }
            
            self.lastSimulationValues = simulationContext.connectorValues
            self.needsSolving = false
            
            if let connectorToSelect = connectorToSelect {
                if selectNewConnectorLabel {
                    self.selectedConnectorLabel = connectorToSelect
                }
            }
        }
        
        func updateFunctionVisualizers(toy: FunctionVisualizerToy, lastSimulationValues: [Connector: SimulationContext.ResolvedValue]) {
            // Now, get the state needed to update the ghosts
            var inputConnectorStates: [Connector: ConnectorState] = [:]
            for inputConnector in toy.inputConnectors() {
                guard let inputConnectorLabel = self.connectorToLabel[inputConnector],
                    let initialValue = lastSimulationValues[inputConnector] else {
                        // Somehow this input connector isn't in our context. We've got to bail
                    return
                }
                inputConnectorStates[inputConnector] = ConnectorState(Value: initialValue, Scale: inputConnectorLabel.scale)
            }
            
            // Construct a list of all connectors in order of priority. It is okay to have duplicates
            // First the selected connector
            var allConnectors = [self.selectedConnectorLabel?.connector].flatMap({$0})
            // Then the ones from the values map
            allConnectors += values.map{ (connector, value) in
                return connector
            }
            // Then the ones from the last context
            allConnectors += self.connectorLabels.map{ connectorLabel in
                return connectorLabel.connector
            }
            // Filter out any of the output connectors, to make sure they are last priority
            let outputConnectors = toy.outputConnectors()
            let pathToOutputConnectors = connectorsFromToyInputsToOutputs(toy)
            allConnectors = allConnectors.filter({ connector -> Bool in
                return !outputConnectors.contains(connector) && !pathToOutputConnectors.contains(connector)
            })
            allConnectors = allConnectors + Array(pathToOutputConnectors) + outputConnectors
            
            toy.update(currentStates: inputConnectorStates) { (inputValues: [Connector: Double], variables: [Connector: String]?) -> SimulationContext in
                // The toy calls this each time it wants to know what the outputs end up being for a given input
                
                // Set up the context
                let simulationContext = SimulationContext(connectorResolvedCallback: { (_, _) in },
                    connectorConflictCallback: { (_, _) in })
                simulationContext.rewriteExpressions = false
                simulationContext.shortcutOperations = false
                
                func expression(for connector: Connector, value: Double) -> DDExpression {
                    if let variables = variables, let variableName = variables[connector] {
                        return DDExpression.variableExpression(withVariable: variableName)
                    } else {
                        return constantExpression(number: value)
                    }
                }
                
                // First the new values on the inputs
                for (inputConnector, inputValue) in inputValues {
                    simulationContext.setConnectorValue(connector: inputConnector, value: (DoubleValue: inputValue, Expression: expression(for:inputConnector, value:inputValue), WasDependent: false, Informant: nil))
                }
                
                // Go through all the connectors in order and fill in previous values until they are all resolved
                for connector in allConnectors {
                    if simulationContext.connectorValues[connector] != nil {
                        // This connector has already been resolved
                        continue
                    }
                    if let value = (values[connector] ?? lastSimulationValues[connector]?.DoubleValue) {
                        simulationContext.setConnectorValue(connector: connector, value: (DoubleValue: value, Expression: expression(for:connector, value:value), WasDependent: false, Informant: nil))
                    }
                }
                
                return simulationContext
            }
        }
        
        
        
        var ranSolver = false
        while (self.needsLayout || self.needsSolving) {
            // First, we layout. This way, if solving generates a new connector then it will be pointed in a sane direction
            // But, solving means we might need to layout, and so on...
            if (self.needsLayout) {
                layoutConstraintViews()
            }
            if (self.needsSolving) {
                runSolver()
                ranSolver = true
            }
        }
        
        if (self.needsRebuildConnectionLayers) {
            rebuildAllConnectionLayers()
        }
        
        if let lastSimulationValues = self.lastSimulationValues, ranSolver {
            for toy in self.toys {
                toy.update(values: lastSimulationValues)
                if let toy = toy as? FunctionVisualizerToy {
                    updateFunctionVisualizers(toy: toy, lastSimulationValues: lastSimulationValues)
                }
            }
            
            // We first make a map from value DDExpressions to the formatted value
            var formattedValues: [DDExpression : String] = [:]
            for label in self.connectorLabels {
                if let value = lastSimulationValues[label.connector] {
                    if value.Expression.expressionType() == .number {
                        formattedValues[value.Expression] = label.name ?? label.valueLabel.text
                    }
                }
            }
            
            for label in self.connectorLabels {
                var displayedEquation = false
                if let value = lastSimulationValues[label.connector] {
                    if value.Expression.expressionType() == .function {
                        if let mathML = mathMLForExpression(expression: value.Expression, formattedValues: formattedValues) {
                            label.displayEquation(mathML: mathML)
                            displayedEquation = true
                        }
                    }
                }
                if !displayedEquation {
                    label.hideEquation()
                }
            }
        }
    }
    
    func createConnectionLayer(startPoint: CGPoint, endPoint: CGPoint, color: UIColor?, isDependent: Bool, arrowHeadPosition: CGFloat?) -> CAShapeLayer {
        let dragLine = CAShapeLayer()
        dragLine.lineWidth = 3
        dragLine.fillColor = nil
        dragLine.lineCap = kCALineCapRound
        dragLine.strokeColor = color?.cgColor ?? UIColor.textColor().cgColor
        
        dragLine.path = createPointingLine(startPoint: startPoint, endPoint: endPoint, dash: isDependent, arrowHeadPosition: arrowHeadPosition)
        return dragLine
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil, completion: { context in
            self.updateScrollableSize()
        })
    }
    
    func updateScrollableSize() {
        var maxY: CGFloat = 0
        var maxX: CGFloat = self.view.bounds.width
        for view in connectorLabels {
            maxY = max(maxY, view.frame.maxY)
            maxX = max(maxX, view.frame.maxX)
        }
        for view in constraintViews {
            maxY = max(maxY, view.frame.maxY)
            maxX = max(maxX, view.frame.maxX)
        }
        
        self.scrollView.contentSize = CGSize(width: maxX, height: maxY + self.view.bounds.height)
    }
    
    var toys: [Toy] = [] {
        didSet {
            var hasGhosts = false
            for toy in toys {
                if let toy = toy as? GhostableToy {
                    hasGhosts = true
                    toy.ghostsHidden = !showGhosts
                }
            }
            ghostButton.isHidden = !hasGhosts
        }
    }
    
    func connectorIsForToy(connector: Connector) -> Bool {
        for toy in self.toys {
            if toy.outputConnectors().contains(connector) || toy.inputConnectors().contains(connector) {
                return true
            }
        }
        return false
    }

    var showGhosts: Bool = false {
        didSet {
            ghostButton?.isSelected = showGhosts
            for toy in self.toys {
                if let toy = toy as? GhostableToy {
                    toy.ghostsHidden = !showGhosts
                }
            }
        }
    }

    func ghostButtonTapped() {
        showGhosts = !showGhosts
    }
    
    var nameCanvas: NameCanvasViewController?
    
    func showNameCanvas() {
        let canvasViewController = NameCanvasViewController()
        self.nameCanvas = canvasViewController
        canvasViewController.delegate = self;
        
        canvasViewController.transitioningDelegate = self
        canvasViewController.modalPresentationStyle = .custom
        
        self.present(canvasViewController, animated: true, completion: nil)
    }
    
    func nameCanvasViewControllerDidFinish(nameCanvasViewController: NameCanvasViewController) {
        guard let canvasViewController = self.nameCanvas, canvasViewController == nameCanvasViewController else {
            return
        }
        
        if let selectedConnectorLabel = self.selectedConnectorLabel {
            let scale = UIScreen.main.scale
            let height = selectedConnectorLabel.valueLabel.frame.size.height
            
            if let nameImage = canvasViewController.renderedImage(pointHeight: height, scale: scale, color: UIColor.textColor().cgColor),
                let selectedNameImage = canvasViewController.renderedImage(pointHeight: height, scale: scale, color: UIColor.selectedTextColor().cgColor) {
                    
                    selectedConnectorLabel.nameImages = (image: nameImage, selectedImage: selectedNameImage)
            } else {
                selectedConnectorLabel.nameImages = nil
            }
        }
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animator = NameCanvasAnimator()
        animator.presenting = true
        return animator
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return NameCanvasAnimator()
    }
}

