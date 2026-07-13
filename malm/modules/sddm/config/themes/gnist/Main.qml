import QtQuick
import QtQuick.Window

Rectangle {
    id: root
    width:  Screen.width
    height: Screen.height

    property color bgColor:     config.backgroundColor
    property color fgColor:     config.foregroundColor
    property color accentColor: config.accentColor
    property color innerColor:  Qt.rgba(bgColor.r, bgColor.g, bgColor.b, 0.8)
    property color errorColor:  "#c34043"
    property int   fontSize:    parseInt(config.fontSize) || 12
    property int   sessionIdx:  0

    readonly property int fieldW: 420
    readonly property int fieldH: 52
    readonly property var focusOrder: [userField, pwField, sessionBox, rebootBtn, powerOffBtn]

    function fgAlpha(a) { return Qt.rgba(fgColor.r, fgColor.g, fgColor.b, a) }

    function focusNext(current) {
        var i = focusOrder.indexOf(current)
        focusOrder[(i + 1) % focusOrder.length].forceActiveFocus()
    }
    function focusPrev(current) {
        var i = focusOrder.indexOf(current)
        focusOrder[(i + focusOrder.length - 1) % focusOrder.length].forceActiveFocus()
    }

    function doLogin() {
        if (userField.fieldText === "") { userField.forceActiveFocus(); return }
        sddm.login(userField.fieldText, pwField.fieldText, sessionIdx)
    }

    component InputField: FocusScope {
        id: field
        width: root.fieldW; height: root.fieldH

        property alias fieldText:         input.text
        property alias echoMode:          input.echoMode
        property alias passwordCharacter: input.passwordCharacter
        property string placeholder:  ""
        property string initialText:  ""
        signal submitted()

        Rectangle {
            anchors.fill: parent
            color: root.innerColor
            border.color: input.activeFocus ? root.accentColor : root.fgAlpha(0.5)
            border.width: input.activeFocus ? 2 : 1
            radius: 0

            MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

            Text {
                anchors.centerIn: parent
                text: field.placeholder
                font.family: config.fontName; font.pixelSize: root.fontSize
                color: root.fgAlpha(0.35)
                visible: input.text === ""
            }

            TextInput {
                id: input
                focus: true
                anchors.fill: parent; anchors.margins: 12
                z: 1
                passwordCharacter: "•"
                font.family: config.fontName; font.pixelSize: root.fontSize
                color: root.fgColor
                selectionColor: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment:   TextInput.AlignVCenter
                clip: true
                Keys.onTabPressed:    root.focusNext(field)
                Keys.onBacktabPressed: root.focusPrev(field)
                Keys.onReturnPressed: field.submitted()
            }
        }
    }

    component PowerButton: Rectangle {
        id: btn
        width: 100; height: 30
        color: "transparent"
        border.color: activeFocus || hov ? root.accentColor : root.fgAlpha(0.25)
        border.width: activeFocus ? 2 : 1
        radius: 0

        property bool   hov:   false
        property string label: ""
        signal activated()

        Keys.onTabPressed:    root.focusNext(btn)
        Keys.onBacktabPressed: root.focusPrev(btn)
        Keys.onReturnPressed: activated()

        Text {
            anchors.centerIn: parent
            text: btn.label
            font.family: config.fontName; font.pixelSize: root.fontSize - 1
            color: btn.activeFocus || btn.hov ? root.accentColor : root.fgAlpha(0.45)
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: btn.hov = true
            onExited:  btn.hov = false
            onClicked: btn.activated()
        }
    }

    ListView {
        id: sessionList
        model: sessionModel
        currentIndex: sessionIdx
        opacity: 0; width: 1; height: 1
        delegate: Item { property string sessionName: model.name }
    }

    Image {
        id: bg
        anchors.fill: parent
        source: "background"
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color:   bgColor
        opacity: 0.60
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:              parent.top
        anchors.topMargin:        parent.height * 0.18
        spacing: 4

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: config.fontName
            font.pixelSize: 80
            color: fgColor
            Component.onCompleted: text = Qt.formatTime(new Date(), "HH:mm")
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm")
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
            font.family: config.fontName
            font.pixelSize: fontSize + 2
            color: fgAlpha(0.65)
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        InputField {
            id: userField
            placeholder: "Username"
            onSubmitted: pwField.forceActiveFocus()
        }

        InputField {
            id: pwField
            placeholder: "Password"
            echoMode: TextInput.Password
            onSubmitted: doLogin()
        }

        Rectangle {
            id: sessionBox
            width: fieldW; height: fieldH
            color: "transparent"
            border.color: activeFocus ? accentColor : fgAlpha(0.3)
            border.width: activeFocus ? 2 : 1
            radius: 0

            Keys.onTabPressed:    focusNext(sessionBox)
            Keys.onBacktabPressed: focusPrev(sessionBox)
            Keys.onLeftPressed:  sessionIdx = (sessionIdx + sessionModel.rowCount() - 1) % sessionModel.rowCount()
            Keys.onRightPressed: sessionIdx = (sessionIdx + 1) % sessionModel.rowCount()

            Row {
                anchors.centerIn: parent
                spacing: 14

                Text {
                    text: "‹"
                    font.family: config.fontName; font.pixelSize: fontSize + 2
                    color: fgAlpha(0.5)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sessionBox.forceActiveFocus()
                            sessionIdx = (sessionIdx + sessionModel.rowCount() - 1) % sessionModel.rowCount()
                        }
                    }
                }

                Text {
                    text: sessionList.currentItem ? sessionList.currentItem.sessionName : "—"
                    font.family: config.fontName; font.pixelSize: fontSize
                    color: sessionBox.activeFocus ? fgColor : fgAlpha(0.65)
                }

                Text {
                    text: "›"
                    font.family: config.fontName; font.pixelSize: fontSize + 2
                    color: fgAlpha(0.5)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sessionBox.forceActiveFocus()
                            sessionIdx = (sessionIdx + 1) % sessionModel.rowCount()
                        }
                    }
                }
            }
        }

        Text {
            id: errorMsg
            width: fieldW
            horizontalAlignment: Text.AlignHCenter
            font.family: config.fontName; font.pixelSize: fontSize - 1
            color: errorColor
            visible: text !== ""
        }
    }

    Row {
        anchors.bottom:           parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin:     36
        spacing: 12

        PowerButton {
            id: rebootBtn
            label: "Reboot"
            onActivated: sddm.reboot()
        }

        PowerButton {
            id: powerOffBtn
            label: "Power Off"
            onActivated: sddm.powerOff()
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorMsg.text = "Authentication failed"
            pwField.fieldText = ""
            pwField.forceActiveFocus()
        }
    }

    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: {
            if (userField.fieldText !== "") pwField.forceActiveFocus()
            else userField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        sessionIdx = sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
        userField.fieldText = sddm.lastUser
    }
}
