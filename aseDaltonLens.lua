--[[
    libDaltonLens - public domain library - http://daltonlens.org
    no warranty implied use at your own risk

    Author: Nicolas Burrus nicolas@burrus.name

    This is free and unencumbered software released into the public domain.

    Anyone is free to copy, modify, publish, use, compile, sell, or
    distribute this software, either in source code form or as a compiled
    binary, for any purpose, commercial or non-commercial, and by any
    means.

    In jurisdictions that recognize copyright laws, the author or authors
    of this software dedicate any and all copyright interest in the
    software to the public domain. We make this dedication for the benefit
    of the public at large and to the detriment of our heirs and
    successors. We intend this dedication to be an overt act of
    relinquishment in perpetuity of all present and future rights to this
    software under copyright law.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
    OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
    ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.

    For more information, please refer to https://unlicense.org
    --]]
local DLDeficiencies <const> = {
    "PROTANOPIA",
    "DEUTERANOPIA",
    "TRITANOPIA"
}

local brettel_protan_params <const> = {
    rgbCvdFromRgb_1 = {
        0.14980, 1.19548, -0.34528,
        0.10764, 0.84864, 0.04372,
        0.00384, -0.00540, 1.00156
    },
    rgbCvdFromRgb_2 = {
        0.14570, 1.16172, -0.30742,
        0.10816, 0.85291, 0.03892,
        0.00386, -0.00524, 1.00139
    },
    separationPlaneNormalInRgb = { 0.00048, 0.00393, -0.00441 }
}

local brettel_deutan_params <const> = {
    rgbCvdFromRgb_1 = {
        0.36477, 0.86381, -0.22858,
        0.26294, 0.64245, 0.09462,
        -0.02006, 0.02728, 0.99278
    },
    rgbCvdFromRgb_2 = {
        0.37298, 0.88166, -0.25464,
        0.25954, 0.63506, 0.10540,
        -0.01980, 0.02784, 0.99196
    },
    separationPlaneNormalInRgb = { -0.00281, -0.00611, 0.00892 }
}

local brettel_tritan_params <const> = {
    rgbCvdFromRgb_1 = {
        1.01277, 0.13548, -0.14826,
        -0.01243, 0.86812, 0.14431,
        0.07589, 0.80500, 0.11911
    },
    rgbCvdFromRgb_2 = {
        0.93678, 0.18979, -0.12657,
        0.06154, 0.81526, 0.12320,
        -0.37562, 1.12767, 0.24796
    },
    separationPlaneNormalInRgb = { 0.03901, -0.02788, -0.01113 }
}

local dl_vienot_protan_rgbCvd_from_rgb <const> = {
    0.11238, 0.88762, 0.00000,
    0.11238, 0.88762, -0.00000,
    0.00401, -0.00401, 1.00000
}

local dl_vienot_deutan_rgbCvd_from_rgb <const> = {
    0.29275, 0.70725, 0.00000,
    0.29275, 0.70725, -0.00000,
    -0.02234, 0.02234, 1.00000
}

local dl_vienot_tritan_rgbCvd_from_rgb <const> = {
    1.00000, 0.14461, -0.14461,
    0.00000, 0.85924, 0.14076,
    -0.00000, 0.85924, 0.14076
}

local function linearRGB_from_sRGB(v)
    local fv <const> = v / 255.0
    if fv < 0.04045 then
        return fv / 12.92
    end
    return ((fv + 0.055) / 1.055) ^ 2.4
end

local function sRGB_from_linearRGB(v)
    if v <= 0.0 then return 0.0 end
    if v >= 1.0 then return 1.0 end
    if v < 0.0031308 then
        return v * 12.92
    end
    return (v ^ (1.0 / 2.4)) * 1.055 - 0.055
end

local function dl_simulate_cvd_brettel1997(deficiency, severity, srgba_image)
    local params = nil
    if deficiency == "DEUTERANOPIA" then
        params = brettel_deutan_params
    elseif deficiency == "TRITANOPIA" then
        params = brettel_tritan_params
    else
        params = brettel_protan_params
    end

    local n <const> = params.separationPlaneNormalInRgb

    local composeHex <const> = app.pixelColor.rgba
    local decompAlpha <const> = app.pixelColor.rgbaA
    local decompBlue <const> = app.pixelColor.rgbaB
    local decompGreen <const> = app.pixelColor.rgbaG
    local decompRed <const> = app.pixelColor.rgbaR
    local floor <const> = math.floor

    ---@type table<integer, integer>
    local dict <const> = {}
    local target <const> = srgba_image:clone()
    if severity <= 0.0 then return target end
    local useLerp <const> = severity < 0.999999
    local u <const> = 1.0 - severity

    local pixels <const> = target:pixels()
    for pixel in pixels do
        local hex0 <const> = pixel()
        local hex1 = 0x0
        if dict[hex0] then
            hex1 = dict[hex0]
        else
            local rgb <const> = {
                linearRGB_from_sRGB(decompRed(hex0)),
                linearRGB_from_sRGB(decompGreen(hex0)),
                linearRGB_from_sRGB(decompBlue(hex0))
            }

            -- Check on which plane we should project by comparing wih the
            -- separation plane normal.
            local dotWithSepPlane <const> = rgb[1] * n[1]
                + rgb[2] * n[2]
                + rgb[3] * n[3]
            local rgbCvdFromRgb = nil
            if dotWithSepPlane >= 0 then
                rgbCvdFromRgb = params.rgbCvdFromRgb_1
            else
                rgbCvdFromRgb = params.rgbCvdFromRgb_2
            end

            local rgb_cvd <const> = {
                rgbCvdFromRgb[1] * rgb[1] +
                rgbCvdFromRgb[2] * rgb[2] +
                rgbCvdFromRgb[3] * rgb[3],

                rgbCvdFromRgb[4] * rgb[1] +
                rgbCvdFromRgb[5] * rgb[2] +
                rgbCvdFromRgb[6] * rgb[3],

                rgbCvdFromRgb[7] * rgb[1] +
                rgbCvdFromRgb[8] * rgb[2] +
                rgbCvdFromRgb[9] * rgb[3]
            }

            -- Apply the severity factor as a linear interpolation.
            -- It's the same to do it in the RGB space or in the LMS
            -- space since it's a linear transform.
            if useLerp then
                rgb_cvd[1] = u * rgb[1] + rgb_cvd[1] * severity
                rgb_cvd[2] = u * rgb[2] + rgb_cvd[2] * severity
                rgb_cvd[3] = u * rgb[3] + rgb_cvd[3] * severity
            end

            hex1 = composeHex(
                floor(sRGB_from_linearRGB(rgb_cvd[1]) * 255 + 0.5),
                floor(sRGB_from_linearRGB(rgb_cvd[2]) * 255 + 0.5),
                floor(sRGB_from_linearRGB(rgb_cvd[3]) * 255 + 0.5),
                decompAlpha(hex0))
            dict[hex0] = hex1
        end

        pixel(hex1)
    end

    return target
end

local function dl_simulate_cvd_vienot1999(deficiency, severity, srgba_image)
    local rgbCvd_from_rgb = nil
    if deficiency == "DEUTERANOPIA" then
        rgbCvd_from_rgb = dl_vienot_deutan_rgbCvd_from_rgb
    elseif deficiency == "TRITANOPIA" then
        rgbCvd_from_rgb = dl_vienot_tritan_rgbCvd_from_rgb
    else
        rgbCvd_from_rgb = dl_vienot_protan_rgbCvd_from_rgb
    end

    local pixelColor <const> = app.pixelColor
    local composeHex <const> = pixelColor.rgba
    local decompAlpha <const> = pixelColor.rgbaA
    local decompBlue <const> = pixelColor.rgbaB
    local decompGreen <const> = pixelColor.rgbaG
    local decompRed <const> = pixelColor.rgbaR
    local floor <const> = math.floor

    ---@type table<integer, integer>
    local dict <const> = {}
    local target <const> = srgba_image:clone()
    if severity <= 0.0 then return target end
    local useLerp <const> = severity < 0.999999
    local u <const> = 1.0 - severity

    local pixels <const> = target:pixels()
    for pixel in pixels do
        local hex0 <const> = pixel()
        local hex1 = 0x0
        if dict[hex0] then
            hex1 = dict[hex0]
        else
            local rgb <const> = {
                linearRGB_from_sRGB(decompRed(hex0)),
                linearRGB_from_sRGB(decompGreen(hex0)),
                linearRGB_from_sRGB(decompBlue(hex0))
            }

            local rgb_cvd <const> = {
                rgbCvd_from_rgb[1] * rgb[1] +
                rgbCvd_from_rgb[2] * rgb[2] +
                rgbCvd_from_rgb[3] * rgb[3],

                rgbCvd_from_rgb[4] * rgb[1] +
                rgbCvd_from_rgb[5] * rgb[2] +
                rgbCvd_from_rgb[6] * rgb[3],

                rgbCvd_from_rgb[7] * rgb[1] +
                rgbCvd_from_rgb[8] * rgb[2] +
                rgbCvd_from_rgb[9] * rgb[3]
            }

            if useLerp then
                rgb_cvd[1] = u * rgb[1] + rgb_cvd[1] * severity
                rgb_cvd[2] = u * rgb[2] + rgb_cvd[2] * severity
                rgb_cvd[3] = u * rgb[3] + rgb_cvd[3] * severity
            end

            hex1 = composeHex(
                floor(sRGB_from_linearRGB(rgb_cvd[1]) * 255 + 0.5),
                floor(sRGB_from_linearRGB(rgb_cvd[2]) * 255 + 0.5),
                floor(sRGB_from_linearRGB(rgb_cvd[3]) * 255 + 0.5),
                decompAlpha(hex0))
            dict[hex0] = hex1
        end

        pixel(hex1)
    end

    return target
end

local function dl_simulate_cvd(deficiency, severity, srgba_image)
    if deficiency == "TRITANOPIA" then
        return dl_simulate_cvd_brettel1997(deficiency, severity, srgba_image)
    else
        return dl_simulate_cvd_vienot1999(deficiency, severity, srgba_image)
    end
end

local defaults <const> = {
    deficiency = "PROTANOPIA",
    severity = 100,
}

local dlg <const> = Dialog { title = "Simulate CVD" }

dlg:combobox {
    id = "deficiency",
    label = "Deficiency:",
    option = defaults.deficiency,
    options = DLDeficiencies
}

dlg:slider {
    id = "severity",
    label = "Severity:",
    min = 0,
    max = 100,
    value = defaults.severity
}

dlg:button {
    id = "confirm",
    text = "&OK",
    focus = true,
    onclick = function()
        local activeSprite <const> = app.sprite
        if not activeSprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local colorSpace <const> = activeSprite.colorSpace
        if colorSpace ~= ColorSpace { sRGB = true } then
            app.alert {
                title = "Error",
                text = {
                    "Only sRGB color space is supported.",
                    "Convert to sRGB in Sprite Properties."
                }
            }
            return
        end

        local actFrObj <const> = app.frame or activeSprite.frames[1]
        local actFrIdx <const> = actFrObj.frameNumber

        local args <const> = dlg.data
        local deficiency <const> = args.deficiency
            or defaults.deficiency --[[@as string]]
        local severity <const> = args.severity
            or defaults.severity --[[@as integer]]

        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local dupSprite <const> = Sprite(activeSprite)
        dupSprite.filename = "CVD Simulation"
        app.sprite = dupSprite

        app.command.ChangePixelFormat { format = "rgb" }
        app.command.MaskAll()
        app.command.FlattenLayers { visibleOnly = true }
        app.command.DeselectMask()
        app.command.FitScreen()

        local sev01 <const> = severity * 0.01
        local frames <const> = dupSprite.frames
        local sourceLayer <const> = dupSprite.layers[1]
        sourceLayer.name = "original"
        local targetLayer <const> = dupSprite:newLayer()
        targetLayer.name = deficiency:lower()

        local lenFrames <const> = #frames
        local i = 0
        while i < lenFrames do
            i = i + 1
            local frame <const> = frames[i]
            local sourceCel <const> = sourceLayer:cel(frame)
            if sourceCel then
                local sourceImage <const> = sourceCel.image
                local sourcePos <const> = sourceCel.position
                local targetImage <const> = dl_simulate_cvd(deficiency, sev01, sourceImage)
                dupSprite:newCel(targetLayer, frame, targetImage, sourcePos)
            end
        end

        local appPrefs <const> = app.preferences
        if appPrefs then
            local docPrefs <const> = appPrefs.document(activeSprite)
            if docPrefs then
                local onionSkinPrefs <const> = docPrefs.onionskin
                if onionSkinPrefs then
                    onionSkinPrefs.loop_tag = false
                end

                local thumbPrefs <const> = docPrefs.thumbnails
                if thumbPrefs then
                    thumbPrefs.enabled = true
                    thumbPrefs.zoom = 1
                    thumbPrefs.overlay_enabled = true
                end
            end
        end

        app.frame = dupSprite.frames[actFrIdx]
        app.refresh()
    end
}

dlg:button {
    id = "cancel",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show {
    autoscrollbars = false,
    wait = false
}