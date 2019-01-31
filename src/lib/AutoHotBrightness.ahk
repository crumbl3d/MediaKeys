#include %A_LineFile%\..\OSD.ahk

class AutoHotBrightness {
	; Based on https://github.com/qwerty12/AutoHotkeyScripts/tree/master/LaptopBrightnessSetter
	static _WM_POWERBROADCAST := 0x218, hPowrprofMod := DllCall("LoadLibrary", "Str", "powrprof.dll", "Ptr")
	static _osdHwnd := 0, _stepSize := 10

	__New() {
		if (AutoHotBrightness.GetAcStatus(AC))
			this._AC := AC
		; Sadly the callback passed to *PowerSettingRegister*Notification runs on a new thread
		if ((this.pwrAcNotifyHandle := DllCall("RegisterPowerSettingNotification", "Ptr", A_ScriptHwnd, "Ptr", AutoHotBrightness._GUID_ACDC_POWER_SOURCE(), "UInt", DEVICE_NOTIFY_WINDOW_HANDLE := 0x00000000, "Ptr")))
			OnMessage(this._WM_POWERBROADCAST, ((this.pwrBroadcastFunc := ObjBindMethod(this, "_On_WM_POWERBROADCAST"))))
	}

	__Delete() {
		if (this.pwrAcNotifyHandle) {
			OnMessage(AutoHotBrightness._WM_POWERBROADCAST, this.pwrBroadcastFunc, 0),
			DllCall("UnregisterPowerSettingNotification", "Ptr", this.pwrAcNotifyHandle),
			this.pwrAcNotifyHandle := 0,
			this.pwrBroadcastFunc := ""
		}
	}

	GetBrightnessLevel(autoDcOrAc := -1, ptrAnotherScheme := 0) {
		currSchemeGuid := 0
		AutoHotBrightness._GetCurrentSchemeGuid(currSchemeGuid, AC, autoDcOrAc, ptrAnotherScheme)
		if (!currSchemeGuid)
			return -1
		ret := 0
		if (!AutoHotBrightness._GetCurrentBrightnessLevel(currSchemeGuid, AC, ret))
			ret := -1
		DllCall("LocalFree", "Ptr", currSchemeGuid, "Ptr")
		return ret
	}

	SetBrightnessLevel(value, jump := false, showOSD := true, autoDcOrAc := -1, ptrAnotherScheme := 0) {
		static PowerSetActiveScheme := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerSetActiveScheme", "Ptr"),
		       PowerWriteACValueIndex := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerWriteACValueIndex", "Ptr"),
		       PowerWriteDCValueIndex := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerWriteDCValueIndex", "Ptr"),
		       PowerApplySettingChanges := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerApplySettingChanges", "Ptr")

		if (value == 0 && !jump) {
			if (showOSD)
				OSD.ShowBrightnessOSD()
			return
		}

		currSchemeGuid := 0
		AutoHotBrightness._GetCurrentSchemeGuid(currSchemeGuid, AC, autoDcOrAc, ptrAnotherScheme)
		if (!currSchemeGuid)
			return

		currBrightness := 0
		if (jump || AutoHotBrightness._GetCurrentBrightnessLevel(currSchemeGuid, AC, currBrightness)) {
			minBrightness := AutoHotBrightness.GetMinBrightnessLevel(),
			maxBrightness := AutoHotBrightness.GetMaxBrightnessLevel()
			
			if (jump || !((currBrightness == maxBrightness && value > 0) || (currBrightness == minBrightness && value < minBrightness))) {
				if (currBrightness + value > maxBrightness)
					value := maxBrightness
				else if (currBrightness + value < minBrightness)
					value := minBrightness
				else
					value += currBrightness

				if (DllCall(AC ? PowerWriteACValueIndex : PowerWriteDCValueIndex, "Ptr", 0, "Ptr", currSchemeGuid, "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt", value, "UInt") == 0) {
					; PowerApplySettingChanges is undocumented and exists only in Windows 8+. Since both the Power control panel and the brightness slider use this, we'll do the same, but fallback to PowerSetActiveScheme if on Windows 7 or something
					if (!PowerApplySettingChanges || DllCall(PowerApplySettingChanges, "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt") != 0)
						DllCall(PowerSetActiveScheme, "Ptr", 0, "Ptr", currSchemeGuid, "UInt")
				}
			}

			if (showOSD)
				OSD.ShowBrightnessOSD()
		}

		DllCall("LocalFree", "Ptr", currSchemeGuid, "Ptr")
	}

	GetStepSize() {
		return AutoHotBrightness._stepSize
	}

	SetStepSize(value) {
		if (value > 0)
			AutoHotBrightness._stepSize := value
	}

	StepUp(showOSD := true) {
		AutoHotBrightness.SetBrightnessLevel(+AutoHotBrightness._stepSize, false, showOSD)
	}

	StepDown(showOSD := true) {
		AutoHotBrightness.SetBrightnessLevel(-AutoHotBrightness._stepSize, false, showOSD)
	}

	GetAcStatus(ByRef acStatus) {
		static SystemPowerStatus
		if (!VarSetCapacity(SystemPowerStatus))
			VarSetCapacity(SystemPowerStatus, 12)
		if (DllCall("GetSystemPowerStatus", "Ptr", &SystemPowerStatus)) {
			acStatus := NumGet(SystemPowerStatus, 0, "UChar") == 1
			return true
		}
		return false
	}

	GetDefaultBrightnessIncrement() {
		static ret := 10
		DllCall("powrprof\PowerReadValueIncrement", "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", ret, "UInt")
		return ret
	}

	GetMinBrightnessLevel() {
		static ret := -1
		if (ret == -1 && DllCall("powrprof\PowerReadValueMin", "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", ret, "UInt"))
			ret := 0
		return ret
	}

	GetMaxBrightnessLevel() {
		static ret := -1
		if (ret == -1 && DllCall("powrprof\PowerReadValueMax", "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", ret, "UInt"))
			ret := 100
		return ret
	}

	_GetCurrentSchemeGuid(ByRef currSchemeGuid, ByRef AC, autoDcOrAc := -1, ptrAnotherScheme := 0) {
		static PowerGetActiveScheme := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerGetActiveScheme", "Ptr")

		currSchemeGuid := 0
		AC := false
		if (!ptrAnotherScheme ? DllCall(PowerGetActiveScheme, "Ptr", 0, "Ptr*", currSchemeGuid, "UInt") == 0 : DllCall("powrprof\PowerDuplicateScheme", "Ptr", 0, "Ptr", ptrAnotherScheme, "Ptr*", currSchemeGuid, "UInt") == 0) {
			if (autoDcOrAc == -1) {
				if (this != AutoHotBrightness)
					AC := this._AC
				else if (!AutoHotBrightness.GetAcStatus(AC)) {
					DllCall("LocalFree", "Ptr", currSchemeGuid, "Ptr")
					currSchemeGuid := 0
					AC := false
					return
				}
			} else
				AC := !!autoDcOrAc
		}
	}

	_GetCurrentBrightnessLevel(schemeGuid, AC, ByRef currBrightness) {
		static PowerReadACValueIndex := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerReadACValueIndex", "Ptr"),
		       PowerReadDCValueIndex := DllCall("GetProcAddress", "Ptr", AutoHotBrightness.hPowrprofMod, "AStr", "PowerReadDCValueIndex", "Ptr")
		return DllCall(AC ? PowerReadACValueIndex : PowerReadDCValueIndex, "Ptr", 0, "Ptr", schemeGuid, "Ptr", AutoHotBrightness._GUID_VIDEO_SUBGROUP(), "Ptr", AutoHotBrightness._GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS(), "UInt*", currBrightness, "UInt") == 0
	}

	_On_WM_POWERBROADCAST(wParam, lParam) {
		;OutputDebug % &this
		if (wParam == 0x8013 && lParam && NumGet(lParam+0, 0, "UInt") == NumGet(AutoHotBrightness._GUID_ACDC_POWER_SOURCE()+0, 0, "UInt")) {
			; PBT_POWERSETTINGCHANGE and a lazy comparison
			this._AC := NumGet(lParam+0, 20, "UChar") == 0
			return true
		}
	}

	_GUID_VIDEO_SUBGROUP() {
		static GUID_VIDEO_SUBGROUP__
		if (!VarSetCapacity(GUID_VIDEO_SUBGROUP__)) {
			VarSetCapacity(GUID_VIDEO_SUBGROUP__, 16),
			NumPut(0x7516B95F, GUID_VIDEO_SUBGROUP__, 0, "UInt"), NumPut(0x4464F776, GUID_VIDEO_SUBGROUP__, 4, "UInt"),
			NumPut(0x1606538C, GUID_VIDEO_SUBGROUP__, 8, "UInt"), NumPut(0x99CC407F, GUID_VIDEO_SUBGROUP__, 12, "UInt")
		}
		return &GUID_VIDEO_SUBGROUP__
	}

	_GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS() {
		static GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__
		if (!VarSetCapacity(GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__)) {
			VarSetCapacity(GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 16),
			NumPut(0xADED5E82, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 0, "UInt"), NumPut(0x4619B909, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 4, "UInt"),
			NumPut(0xD7F54999, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 8, "UInt"), NumPut(0xCB0BAC1D, GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__, 12, "UInt")
		}
		return &GUID_DEVICE_POWER_POLICY_VIDEO_BRIGHTNESS__
	}

	_GUID_ACDC_POWER_SOURCE() {
		static GUID_ACDC_POWER_SOURCE_
		if (!VarSetCapacity(GUID_ACDC_POWER_SOURCE_)) {
			VarSetCapacity(GUID_ACDC_POWER_SOURCE_, 16),
			NumPut(0x5D3E9A59, GUID_ACDC_POWER_SOURCE_, 0, "UInt"), NumPut(0x4B00E9D5, GUID_ACDC_POWER_SOURCE_, 4, "UInt"),
			NumPut(0x34FFBDA6, GUID_ACDC_POWER_SOURCE_, 8, "UInt"), NumPut(0x486551FF, GUID_ACDC_POWER_SOURCE_, 12, "UInt")
		}
		return &GUID_ACDC_POWER_SOURCE_
	}
}