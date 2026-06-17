import ExcalidrawModel

/// Arrowhead-type selection for arrows. Backed by `currentItem` (defaults for
/// new arrows) and applied to any selected arrows; the published `revision`
/// bump drives the UI, so no extra stored state is needed.
public extension EditorModel {
    var startArrowhead: Arrowhead? {
        controller.currentItem.startArrowhead
    }

    var endArrowhead: Arrowhead? {
        controller.currentItem.endArrowhead
    }

    func setStartArrowhead(_ head: Arrowhead?) {
        controller.currentItem.startArrowhead = head
        applyToSelection { element in
            if case var .arrow(props) = element.kind {
                props.startArrowhead = head
                element.kind = .arrow(props)
            }
        }
    }

    func setEndArrowhead(_ head: Arrowhead?) {
        controller.currentItem.endArrowhead = head
        applyToSelection { element in
            if case var .arrow(props) = element.kind {
                props.endArrowhead = head
                element.kind = .arrow(props)
            }
        }
    }
}
