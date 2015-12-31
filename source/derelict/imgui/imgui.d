/*
 * Copyright (c) 2015 Derelict Developers
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the names 'Derelict', 'DerelictILUT', nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
module derelict.imgui.imgui;

public
{
    import derelict.imgui.types;
    import derelict.imgui.funcs;
}

private
{
    import derelict.util.loader;

    version(darwin)
        version = MacOSX;
    version(OSX)
        version = MacOSX;
}

private
{
    import derelict.util.loader;
    import derelict.util.system;

    static if(Derelict_OS_Windows)
        enum libNames = "cimgui.dll";
    else static if (Derelict_OS_Mac)
        enum libNames = "cimgui.dylib";
    else static if (Derelict_OS_Linux)
        enum libNames = "cimgui.so";
    else
        static assert(0, "Need to implement imgui libNames for this operating system.");
}

final class DerelictImguiLoader : SharedLibLoader
{
    protected
    {
        override void loadSymbols()
        {
            {
                //search: (ig\S+)
                //replace: bindFunc\(cast\(void**\)&$1, "$1"\);

                bindFunc(cast(void**)&igGetIO, "igGetIO");
                bindFunc(cast(void**)&igGetStyle, "igGetStyle");
                bindFunc(cast(void**)&igGetDrawData, "igGetDrawData");
                bindFunc(cast(void**)&igNewFrame, "igNewFrame");
                bindFunc(cast(void**)&igRender, "igRender");
                bindFunc(cast(void**)&igShutdown, "igShutdown");
                bindFunc(cast(void**)&igShowUserGuide, "igShowUserGuide");
                bindFunc(cast(void**)&igShowStyleEditor, "igShowStyleEditor");
                bindFunc(cast(void**)&igShowTestWindow, "igShowTestWindow");
                bindFunc(cast(void**)&igShowMetricsWindow, "igShowMetricsWindow");

                // Window
                bindFunc(cast(void**)&igBegin, "igBegin");
                bindFunc(cast(void**)&igBegin2, "igBegin2");
                bindFunc(cast(void**)&igEnd, "igEnd");
                bindFunc(cast(void**)&igBeginChild, "igBeginChild");
                bindFunc(cast(void**)&igBeginChildEx, "igBeginChildEx");
                bindFunc(cast(void**)&igEndChild, "igEndChild");
                bindFunc(cast(void**)&igGetContentRegionMax, "igGetContentRegionMax");
				bindFunc(cast(void**)&igGetContentRegionAvail, "igGetContentRegionAvail");
                bindFunc(cast(void**)&igGetContentRegionAvailWidth, "igGetContentRegionAvailWidth");
                bindFunc(cast(void**)&igGetWindowContentRegionMin, "igGetWindowContentRegionMin");
                bindFunc(cast(void**)&igGetWindowContentRegionMax, "igGetWindowContentRegionMax");
                bindFunc(cast(void**)&igGetWindowContentRegionWidth, "igGetWindowContentRegionWidth");
                bindFunc(cast(void**)&igGetWindowDrawList, "igGetWindowDrawList");
                bindFunc(cast(void**)&igGetWindowFont, "igGetWindowFont");
                bindFunc(cast(void**)&igGetWindowFontSize, "igGetWindowFontSize");
                bindFunc(cast(void**)&igSetWindowFontScale, "igSetWindowFontScale");
                bindFunc(cast(void**)&igGetWindowPos, "igGetWindowPos");
                bindFunc(cast(void**)&igGetWindowSize, "igGetWindowSize");
                bindFunc(cast(void**)&igGetWindowWidth, "igGetWindowWidth");
                bindFunc(cast(void**)&igGetWindowHeight, "igGetWindowHeight");
                bindFunc(cast(void**)&igIsWindowCollapsed, "igIsWindowCollapsed");

                bindFunc(cast(void**)&igSetNextWindowPos, "igSetNextWindowPos");
                bindFunc(cast(void**)&igSetNextWindowPosCenter, "igSetNextWindowPosCenter");
                bindFunc(cast(void**)&igSetNextWindowSize, "igSetNextWindowSize");
                bindFunc(cast(void**)&igSetNextWindowCollapsed, "igSetNextWindowCollapsed");
                bindFunc(cast(void**)&igSetNextWindowFocus, "igSetNextWindowFocus");
                bindFunc(cast(void**)&igSetWindowPos, "igSetWindowPos");
                bindFunc(cast(void**)&igSetWindowSize, "igSetWindowSize");
                bindFunc(cast(void**)&igSetNextWindowContentSize, "igSetNextWindowContentSize");
                bindFunc(cast(void**)&igSetNextWindowContentWidth, "igSetNextWindowContentWidth");
                bindFunc(cast(void**)&igSetWindowCollapsed, "igSetWindowCollapsed");
                bindFunc(cast(void**)&igSetWindowFocus, "igSetWindowFocus");
                bindFunc(cast(void**)&igSetWindowPosByName, "igSetWindowPosByName");
                bindFunc(cast(void**)&igSetWindowSize2, "igSetWindowSize2");
                bindFunc(cast(void**)&igSetWindowCollapsed2, "igSetWindowCollapsed2");
                bindFunc(cast(void**)&igSetWindowFocus2, "igSetWindowFocus2");

                bindFunc(cast(void**)&igGetScrollX, "igGetScrollX");
                bindFunc(cast(void**)&igGetScrollY, "igGetScrollY");
                bindFunc(cast(void**)&igGetScrollMaxX, "igGetScrollMaxX");
                bindFunc(cast(void**)&igGetScrollMaxY, "igGetScrollMaxY");
                bindFunc(cast(void**)&igSetScrollX, "igSetScrollX");
                bindFunc(cast(void**)&igSetScrollY, "igSetScrollY");
                bindFunc(cast(void**)&igSetScrollHere, "igSetScrollHere");
                bindFunc(cast(void**)&igSetScrollFromPosY, "igSetScrollFromPosY");
                bindFunc(cast(void**)&igSetKeyboardFocusHere, "igSetKeyboardFocusHere");
                bindFunc(cast(void**)&igSetStateStorage, "igSetStateStorage");
                bindFunc(cast(void**)&igGetStateStorage, "igGetStateStorage");

                bindFunc(cast(void**)&igPushFont, "igPushFont");
                bindFunc(cast(void**)&igPopFont, "igPopFont");
                bindFunc(cast(void**)&igPushStyleColor, "igPushStyleColor");
                bindFunc(cast(void**)&igPopStyleColor, "igPopStyleColor");
                bindFunc(cast(void**)&igPushStyleVar, "igPushStyleVar");
                bindFunc(cast(void**)&igPushStyleVarVec, "igPushStyleVarVec");
                bindFunc(cast(void**)&igPopStyleVar, "igPopStyleVar");

                bindFunc(cast(void**)&igPushItemWidth, "igPushItemWidth");
                bindFunc(cast(void**)&igPopItemWidth, "igPopItemWidth");
                bindFunc(cast(void**)&igCalcItemWidth, "igCalcItemWidth");
                bindFunc(cast(void**)&igPushAllowKeyboardFocus, "igPushAllowKeyboardFocus");
                bindFunc(cast(void**)&igPopAllowKeyboardFocus, "igPopAllowKeyboardFocus");
                bindFunc(cast(void**)&igPushTextWrapPos, "igPushTextWrapPos");
                bindFunc(cast(void**)&igPopTextWrapPos, "igPopTextWrapPos");
                bindFunc(cast(void**)&igPushButtonRepeat, "igPushButtonRepeat");
                bindFunc(cast(void**)&igPopButtonRepeat, "igPopButtonRepeat");

                bindFunc(cast(void**)&igSetTooltip, "igSetTooltip");
                bindFunc(cast(void**)&igSetTooltipV, "igSetTooltipV");
                bindFunc(cast(void**)&igBeginTooltip, "igBeginTooltip");
                bindFunc(cast(void**)&igEndTooltip, "igEndTooltip");

                bindFunc(cast(void**)&igOpenPopup, "igOpenPopup");
                bindFunc(cast(void**)&igBeginPopup, "igBeginPopup");
                bindFunc(cast(void**)&igBeginPopupModal, "igBeginPopupModal");
                bindFunc(cast(void**)&igBeginPopupContextItem, "igBeginPopupContextItem");
                bindFunc(cast(void**)&igBeginPopupContextWindow, "igBeginPopupContextWindow");
                bindFunc(cast(void**)&igBeginPopupContextVoid, "igBeginPopupContextVoid");
                bindFunc(cast(void**)&igEndPopup, "igEndPopup");
                bindFunc(cast(void**)&igCloseCurrentPopup, "igCloseCurrentPopup");

                bindFunc(cast(void**)&igBeginGroup, "igBeginGroup");
                bindFunc(cast(void**)&igEndGroup, "igEndGroup");
                bindFunc(cast(void**)&igSeparator, "igSeparator");
                bindFunc(cast(void**)&igSameLine, "igSameLine");
                bindFunc(cast(void**)&igSpacing, "igSpacing");
                bindFunc(cast(void**)&igDummy, "igDummy");
                bindFunc(cast(void**)&igIndent, "igIndent");
                bindFunc(cast(void**)&igUnindent, "igUnindent");
                bindFunc(cast(void**)&igColumns, "igColumns");
                bindFunc(cast(void**)&igNextColumn, "igNextColumn");
                bindFunc(cast(void**)&igGetColumnIndex, "igGetColumnIndex");
                bindFunc(cast(void**)&igGetColumnOffset, "igGetColumnOffset");
                bindFunc(cast(void**)&igSetColumnOffset, "igSetColumnOffset");
                bindFunc(cast(void**)&igGetColumnWidth, "igGetColumnWidth");
                bindFunc(cast(void**)&igGetColumnsCount, "igGetColumnsCount");
                bindFunc(cast(void**)&igGetCursorPos, "igGetCursorPos");
                bindFunc(cast(void**)&igGetCursorPosX, "igGetCursorPosX");
                bindFunc(cast(void**)&igGetCursorPosY, "igGetCursorPosY");
                bindFunc(cast(void**)&igSetCursorPos, "igSetCursorPos");
                bindFunc(cast(void**)&igSetCursorPosX, "igSetCursorPosX");
                bindFunc(cast(void**)&igSetCursorPosY, "igSetCursorPosY");
                bindFunc(cast(void**)&igGetCursorStartPos, "igGetCursorStartPos");
                bindFunc(cast(void**)&igGetCursorScreenPos, "igGetCursorScreenPos");
                bindFunc(cast(void**)&igSetCursorScreenPos, "igSetCursorScreenPos");
                bindFunc(cast(void**)&igAlignFirstTextHeightToWidgets, "igAlignFirstTextHeightToWidgets");
                bindFunc(cast(void**)&igGetTextLineHeight, "igGetTextLineHeight");
                bindFunc(cast(void**)&igGetTextLineHeightWithSpacing, "igGetTextLineHeightWithSpacing");
                bindFunc(cast(void**)&igGetItemsLineHeightWithSpacing, "igGetItemsLineHeightWithSpacing");

                bindFunc(cast(void**)&igPushIdStr, "igPushIdStr");
                bindFunc(cast(void**)&igPushIdStrRange, "igPushIdStrRange");
                bindFunc(cast(void**)&igPushIdPtr, "igPushIdPtr");
                bindFunc(cast(void**)&igPushIdInt, "igPushIdInt");
                bindFunc(cast(void**)&igPopId, "igPopId");
                bindFunc(cast(void**)&igGetIdStr, "igGetIdStr");
                bindFunc(cast(void**)&igGetIdStrRange, "igGetIdStrRange");
                bindFunc(cast(void**)&igGetIdPtr, "igGetIdPtr");

                bindFunc(cast(void**)&igText, "igText");
                bindFunc(cast(void**)&igTextV, "igTextV");
                bindFunc(cast(void**)&igTextColored, "igTextColored");
                bindFunc(cast(void**)&igTextColoredV, "igTextColoredV");
                bindFunc(cast(void**)&igTextDisabled, "igTextDisabled");
                bindFunc(cast(void**)&igTextDisabledV, "igTextDisabledV");
                bindFunc(cast(void**)&igTextWrapped, "igTextWrapped");
                bindFunc(cast(void**)&igTextWrappedV, "igTextWrappedV");
                bindFunc(cast(void**)&igTextUnformatted, "igTextUnformatted");
                bindFunc(cast(void**)&igLabelText, "igLabelText");
                bindFunc(cast(void**)&igLabelTextV, "igLabelTextV");
                bindFunc(cast(void**)&igBullet, "igBullet");
                bindFunc(cast(void**)&igBulletText, "igBulletText");
                bindFunc(cast(void**)&igBulletTextV, "igBulletTextV");
                bindFunc(cast(void**)&igButton, "igButton");
                bindFunc(cast(void**)&igSmallButton, "igSmallButton");
                bindFunc(cast(void**)&igInvisibleButton, "igInvisibleButton");
                bindFunc(cast(void**)&igImage, "igImage");
                bindFunc(cast(void**)&igImageButton, "igImageButton");
                bindFunc(cast(void**)&igCollapsingHeader, "igCollapsingHeader");
                bindFunc(cast(void**)&igCheckbox, "igCheckbox");
                bindFunc(cast(void**)&igCheckboxFlags, "igCheckboxFlags");
                bindFunc(cast(void**)&igRadioButtonBool, "igRadioButtonBool");
                bindFunc(cast(void**)&igRadioButton, "igRadioButton");
                bindFunc(cast(void**)&igCombo, "igCombo");
                bindFunc(cast(void**)&igCombo2, "igCombo2");
                bindFunc(cast(void**)&igCombo3, "igCombo3");
                bindFunc(cast(void**)&igColorButton, "igColorButton");
                bindFunc(cast(void**)&igColorEdit3, "igColorEdit3");
                bindFunc(cast(void**)&igColorEdit4, "igColorEdit4");
                bindFunc(cast(void**)&igColorEditMode, "igColorEditMode");
                bindFunc(cast(void**)&igPlotLines, "igPlotLines");
                bindFunc(cast(void**)&igPlotLines2, "igPlotLines2");
                bindFunc(cast(void**)&igPlotHistogram, "igPlotHistogram");
                bindFunc(cast(void**)&igPlotHistogram2, "igPlotHistogram2");

                bindFunc(cast(void**)&igSliderFloat, "igSliderFloat");
                bindFunc(cast(void**)&igSliderFloat2, "igSliderFloat2");
                bindFunc(cast(void**)&igSliderFloat3, "igSliderFloat3");
                bindFunc(cast(void**)&igSliderFloat4, "igSliderFloat4");
                bindFunc(cast(void**)&igSliderAngle, "igSliderAngle");
                bindFunc(cast(void**)&igSliderInt, "igSliderInt");
                bindFunc(cast(void**)&igSliderInt2, "igSliderInt2");
                bindFunc(cast(void**)&igSliderInt3, "igSliderInt3");
                bindFunc(cast(void**)&igSliderInt4, "igSliderInt4");
                bindFunc(cast(void**)&igVSliderFloat, "igVSliderFloat");
                bindFunc(cast(void**)&igVSliderInt, "igVSliderInt");

                bindFunc(cast(void**)&igDragFloat, "igDragFloat");
                bindFunc(cast(void**)&igDragFloat2, "igDragFloat2");
                bindFunc(cast(void**)&igDragFloat3, "igDragFloat3");
                bindFunc(cast(void**)&igDragFloat4, "igDragFloat4");
                bindFunc(cast(void**)&igDragFloatRange2, "igDragFloatRange2");
                bindFunc(cast(void**)&igDragInt, "igDragInt");
                bindFunc(cast(void**)&igDragInt2, "igDragInt2");
                bindFunc(cast(void**)&igDragInt3, "igDragInt3");
                bindFunc(cast(void**)&igDragInt4, "igDragInt4");
                bindFunc(cast(void**)&igDragIntRange2, "igDragIntRange2");

                bindFunc(cast(void**)&igInputText, "igInputText");
                bindFunc(cast(void**)&igInputTextMultiline, "igInputTextMultiline");
                bindFunc(cast(void**)&igInputFloat, "igInputFloat");
                bindFunc(cast(void**)&igInputFloat2, "igInputFloat2");
                bindFunc(cast(void**)&igInputFloat3, "igInputFloat3");
                bindFunc(cast(void**)&igInputFloat4, "igInputFloat4");
                bindFunc(cast(void**)&igInputInt, "igInputInt");
                bindFunc(cast(void**)&igInputInt2, "igInputInt2");
                bindFunc(cast(void**)&igInputInt3, "igInputInt3");
                bindFunc(cast(void**)&igInputInt4, "igInputInt4");

                bindFunc(cast(void**)&igTreeNode, "igTreeNode");
                bindFunc(cast(void**)&igTreeNodeStr, "igTreeNodeStr");
                bindFunc(cast(void**)&igTreeNodePtr, "igTreeNodePtr");
                bindFunc(cast(void**)&igTreeNodeStrV, "igTreeNodeStrV");
                bindFunc(cast(void**)&igTreeNodePtrV, "igTreeNodePtrV");
                bindFunc(cast(void**)&igTreePushStr, "igTreePushStr");
                bindFunc(cast(void**)&igTreePushPtr, "igTreePushPtr");
                bindFunc(cast(void**)&igTreePop, "igTreePop");
                bindFunc(cast(void**)&igSetNextTreeNodeOpened, "igSetNextTreeNodeOpened");

                bindFunc(cast(void**)&igSelectable, "igSelectable");
                bindFunc(cast(void**)&igSelectableEx, "igSelectableEx");
                bindFunc(cast(void**)&igListBox, "igListBox");
                bindFunc(cast(void**)&igListBox2, "igListBox2");
                bindFunc(cast(void**)&igListBoxHeader, "igListBoxHeader");
                bindFunc(cast(void**)&igListBoxHeader2, "igListBoxHeader2");
                bindFunc(cast(void**)&igListBoxFooter, "igListBoxFooter");

                bindFunc(cast(void**)&igBeginMainMenuBar, "igBeginMainMenuBar");
                bindFunc(cast(void**)&igEndMainMenuBar, "igEndMainMenuBar");
                bindFunc(cast(void**)&igBeginMenuBar, "igBeginMenuBar");
                bindFunc(cast(void**)&igEndMenuBar, "igEndMenuBar");
                bindFunc(cast(void**)&igBeginMenu, "igBeginMenu");
                bindFunc(cast(void**)&igEndMenu, "igEndMenu");
                bindFunc(cast(void**)&igMenuItem, "igMenuItem");
                bindFunc(cast(void**)&igMenuItemPtr, "igMenuItemPtr");

                bindFunc(cast(void**)&igValueBool, "igValueBool");
                bindFunc(cast(void**)&igValueInt, "igValueInt");
                bindFunc(cast(void**)&igValueUInt, "igValueUInt");
                bindFunc(cast(void**)&igValueFloat, "igValueFloat");
                bindFunc(cast(void**)&igColor, "igColor");
                bindFunc(cast(void**)&igColor2, "igColor2");

                bindFunc(cast(void**)&igLogToTTY, "igLogToTTY");
                bindFunc(cast(void**)&igLogToFile, "igLogToFile");
                bindFunc(cast(void**)&igLogToClipboard, "igLogToClipboard");
                bindFunc(cast(void**)&igLogFinish, "igLogFinish");
                bindFunc(cast(void**)&igLogButtons, "igLogButtons");
                bindFunc(cast(void**)&igLogText, "igLogText");

                bindFunc(cast(void**)&igIsItemHovered, "igIsItemHovered");
                bindFunc(cast(void**)&igIsItemHoveredRect, "igIsItemHoveredRect");
                bindFunc(cast(void**)&igIsItemActive, "igIsItemActive");
                bindFunc(cast(void**)&igIsItemVisible, "igIsItemVisible");
                bindFunc(cast(void**)&igIsAnyItemHovered, "igIsAnyItemHovered");
                bindFunc(cast(void**)&igIsAnyItemActive, "igIsAnyItemActive");
                bindFunc(cast(void**)&igGetItemRectMin, "igGetItemRectMin");
                bindFunc(cast(void**)&igGetItemRectMax, "igGetItemRectMax");
                bindFunc(cast(void**)&igGetItemRectSize, "igGetItemRectSize");
                bindFunc(cast(void**)&igIsWindowHovered, "igIsWindowHovered");
                bindFunc(cast(void**)&igIsWindowFocused, "igIsWindowFocused");
                bindFunc(cast(void**)&igIsRootWindowFocused, "igIsRootWindowFocused");
                bindFunc(cast(void**)&igIsRootWindowOrAnyChildFocused, "igIsRootWindowOrAnyChildFocused");
                bindFunc(cast(void**)&igIsRectVisible, "igIsRectVisible");
                bindFunc(cast(void**)&igIsKeyDown, "igIsKeyDown");
                bindFunc(cast(void**)&igIsKeyPressed, "igIsKeyPressed");
                bindFunc(cast(void**)&igIsMouseDown, "igIsMouseDown");
                bindFunc(cast(void**)&igIsMouseClicked, "igIsMouseClicked");
                bindFunc(cast(void**)&igIsMouseDoubleClicked, "igIsMouseDoubleClicked");
                bindFunc(cast(void**)&igIsMouseReleased, "igIsMouseReleased");
                bindFunc(cast(void**)&igIsMouseHoveringWindow, "igIsMouseHoveringWindow");
                bindFunc(cast(void**)&igIsMouseHoveringAnyWindow, "igIsMouseHoveringAnyWindow");
                bindFunc(cast(void**)&igIsMouseHoveringRect, "igIsMouseHoveringRect");
                bindFunc(cast(void**)&igIsMouseDragging, "igIsMouseDragging");
                bindFunc(cast(void**)&igIsPosHoveringAnyWindow, "igIsPosHoveringAnyWindow");
                bindFunc(cast(void**)&igGetMousePos, "igGetMousePos");
                bindFunc(cast(void**)&igGetMousePosOnOpeningCurrentPopup, "igGetMousePosOnOpeningCurrentPopup");
                bindFunc(cast(void**)&igGetMouseDragDelta, "igGetMouseDragDelta");
                bindFunc(cast(void**)&igResetMouseDragDelta, "igResetMouseDragDelta");
                bindFunc(cast(void**)&igGetMouseCursor, "igGetMouseCursor");
                bindFunc(cast(void**)&igSetMouseCursor, "igSetMouseCursor");
                bindFunc(cast(void**)&igCaptureKeyboardFromApp, "igCaptureKeyboardFromApp");
                bindFunc(cast(void**)&igCaptureMouseFromApp, "igCaptureMouseFromApp");

                bindFunc(cast(void**)&igMemAlloc, "igMemAlloc");
                bindFunc(cast(void**)&igMemFree, "igMemFree");
                bindFunc(cast(void**)&igGetClipboardText, "igGetClipboardText");
                bindFunc(cast(void**)&igSetClipboardText, "igSetClipboardText");

                bindFunc(cast(void**)&igGetTime, "igGetTime");
                bindFunc(cast(void**)&igGetFrameCount, "igGetFrameCount");
                bindFunc(cast(void**)&igGetStyleColName, "igGetStyleColName");
                bindFunc(cast(void**)&igCalcItemRectClosestPoint, "igCalcItemRectClosestPoint");
                bindFunc(cast(void**)&igCalcTextSize, "igCalcTextSize");
                bindFunc(cast(void**)&igCalcListClipping, "igCalcListClipping");

                bindFunc(cast(void**)&igBeginChildFrame, "igBeginChildFrame");
                bindFunc(cast(void**)&igEndChildFrame, "igEndChildFrame");


                bindFunc(cast(void**)&igColorConvertU32ToFloat4, "igColorConvertU32ToFloat4");
                bindFunc(cast(void**)&igColorConvertFloat4ToU32, "igColorConvertFloat4ToU32");
                bindFunc(cast(void**)&igColorConvertRGBtoHSV, "igColorConvertRGBtoHSV");
                bindFunc(cast(void**)&igColorConvertHSVtoRGB, "igColorConvertHSVtoRGB");

                bindFunc(cast(void**)&igGetVersion, "igGetVersion");
                bindFunc(cast(void**)&igGetInternalState, "igGetInternalState");
                bindFunc(cast(void**)&igGetInternalStateSize, "igGetInternalStateSize");
                bindFunc(cast(void**)&igSetInternalState, "igSetInternalState");
            }

            {
                bindFunc(cast(void**)&ImFontAtlas_GetTexDataAsRGBA32, "ImFontAtlas_GetTexDataAsRGBA32");
                bindFunc(cast(void**)&ImFontAtlas_GetTexDataAsAlpha8, "ImFontAtlas_GetTexDataAsAlpha8");
                bindFunc(cast(void**)&ImFontAtlas_SetTexID, "ImFontAtlas_SetTexID");
                bindFunc(cast(void**)&ImFontAtlas_AddFont, "ImFontAtlas_AddFont");
                bindFunc(cast(void**)&ImFontAtlas_AddFontDefault, "ImFontAtlas_AddFontDefault");
                bindFunc(cast(void**)&ImFontAtlas_AddFontFromFileTTF, "ImFontAtlas_AddFontFromFileTTF");
                bindFunc(cast(void**)&ImFontAtlas_AddFontFromMemoryTTF, "ImFontAtlas_AddFontFromMemoryTTF");
                bindFunc(cast(void**)&ImFontAtlas_AddFontFromMemoryCompressedTTF, "ImFontAtlas_AddFontFromMemoryCompressedTTF");
				bindFunc(cast(void**)&ImFontAtlas_AddFontFromMemoryCompressedBase85TTF, "ImFontAtlas_AddFontFromMemoryCompressedBase85TTF");
                bindFunc(cast(void**)&ImFontAtlas_ClearTexData, "ImFontAtlas_ClearTexData");
                bindFunc(cast(void**)&ImFontAtlas_Clear, "ImFontAtlas_Clear");
            }

            bindFunc(cast(void**)&ImDrawList_GetVertexBufferSize, "ImDrawList_GetVertexBufferSize");
            bindFunc(cast(void**)&ImDrawList_GetVertexPtr, "ImDrawList_GetVertexPtr");
            bindFunc(cast(void**)&ImDrawList_GetIndexBufferSize, "ImDrawList_GetIndexBufferSize");
            bindFunc(cast(void**)&ImDrawList_GetIndexPtr, "ImDrawList_GetIndexPtr");
            bindFunc(cast(void**)&ImDrawList_GetCmdSize, "ImDrawList_GetCmdSize");
            bindFunc(cast(void**)&ImDrawList_GetCmdPtr, "ImDrawList_GetCmdPtr");

			bindFunc(cast(void**)&ImDrawList_Clear, "ImDrawList_Clear");
			bindFunc(cast(void**)&ImDrawList_ClearFreeMemory, "ImDrawList_ClearFreeMemory");
			bindFunc(cast(void**)&ImDrawList_PushClipRect, "ImDrawList_PushClipRect");
			bindFunc(cast(void**)&ImDrawList_PushClipRectFullScreen, "ImDrawList_PushClipRectFullScreen");
			bindFunc(cast(void**)&ImDrawList_PopClipRect, "ImDrawList_PopClipRect");
			bindFunc(cast(void**)&ImDrawList_PushTextureID, "ImDrawList_PushTextureID");
			bindFunc(cast(void**)&ImDrawList_PopTextureID, "ImDrawList_PopTextureID");
			bindFunc(cast(void**)&ImDrawList_AddLine, "ImDrawList_AddLine");
			bindFunc(cast(void**)&ImDrawList_AddRect, "ImDrawList_AddRect");
			bindFunc(cast(void**)&ImDrawList_AddRectFilled, "ImDrawList_AddRectFilled");
			bindFunc(cast(void**)&ImDrawList_AddRectFilledMultiColor, "ImDrawList_AddRectFilledMultiColor");
			bindFunc(cast(void**)&ImDrawList_AddTriangleFilled, "ImDrawList_AddTriangleFilled");
			bindFunc(cast(void**)&ImDrawList_AddCircle, "ImDrawList_AddCircle");
			bindFunc(cast(void**)&ImDrawList_AddCircleFilled, "ImDrawList_AddCircleFilled");
			bindFunc(cast(void**)&ImDrawList_AddText, "ImDrawList_AddText");
			bindFunc(cast(void**)&ImDrawList_AddTextExt, "ImDrawList_AddTextExt");
			bindFunc(cast(void**)&ImDrawList_AddImage, "ImDrawList_AddImage");
			bindFunc(cast(void**)&ImDrawList_AddPolyline, "ImDrawList_AddPolyline");
			bindFunc(cast(void**)&ImDrawList_AddConvexPolyFilled, "ImDrawList_AddConvexPolyFilled");
			bindFunc(cast(void**)&ImDrawList_AddBezierCurve, "ImDrawList_AddBezierCurve");
			bindFunc(cast(void**)&ImDrawList_PathClear, "ImDrawList_PathClear");
			bindFunc(cast(void**)&ImDrawList_PathLineTo, "ImDrawList_PathLineTo");
			bindFunc(cast(void**)&ImDrawList_PathLineToMergeDuplicate, "ImDrawList_PathLineToMergeDuplicate");
			bindFunc(cast(void**)&ImDrawList_PathFill, "ImDrawList_PathFill");
			bindFunc(cast(void**)&ImDrawList_PathStroke, "ImDrawList_PathStroke");
			bindFunc(cast(void**)&ImDrawList_PathArcTo, "ImDrawList_PathArcTo");
			bindFunc(cast(void**)&ImDrawList_PathArcToFast, "ImDrawList_PathArcToFast");
			bindFunc(cast(void**)&ImDrawList_PathBezierCurveTo, "ImDrawList_PathBezierCurveTo");
			bindFunc(cast(void**)&ImDrawList_PathRect, "ImDrawList_PathRect");
			bindFunc(cast(void**)&ImDrawList_ChannelsSplit, "ImDrawList_ChannelsSplit");
			bindFunc(cast(void**)&ImDrawList_ChannelsMerge, "ImDrawList_ChannelsMerge");
			bindFunc(cast(void**)&ImDrawList_ChannelsSetCurrent, "ImDrawList_ChannelsSetCurrent");
			bindFunc(cast(void**)&ImDrawList_AddCallback, "ImDrawList_AddCallback");
			bindFunc(cast(void**)&ImDrawList_AddDrawCmd, "ImDrawList_AddDrawCmd");
			bindFunc(cast(void**)&ImDrawList_PrimReserve, "ImDrawList_PrimReserve");
			bindFunc(cast(void**)&ImDrawList_PrimRect, "ImDrawList_PrimRect");
			bindFunc(cast(void**)&ImDrawList_PrimRectUV, "ImDrawList_PrimRectUV");
			bindFunc(cast(void**)&ImDrawList_PrimVtx, "ImDrawList_PrimVtx");
			bindFunc(cast(void**)&ImDrawList_PrimWriteVtx, "ImDrawList_PrimWriteVtx");
			bindFunc(cast(void**)&ImDrawList_PrimWriteIdx, "ImDrawList_PrimWriteIdx");
			bindFunc(cast(void**)&ImDrawList_UpdateClipRect, "ImDrawList_UpdateClipRect");
			bindFunc(cast(void**)&ImDrawList_UpdateTextureID, "ImDrawList_UpdateTextureID");

            bindFunc(cast(void**)&ImGuiIO_AddInputCharacter, "ImGuiIO_AddInputCharacter");
            bindFunc(cast(void**)&ImGuiIO_AddInputCharactersUTF8, "ImGuiIO_AddInputCharactersUTF8");


            bindFunc(cast(void**)&igGetCurrentWindowRead, "igGetCurrentWindowRead");
			bindFunc(cast(void**)&igGetCurrentWindow, "igGetCurrentWindow");
			bindFunc(cast(void**)&igGetParentWindow, "igGetParentWindow");
			bindFunc(cast(void**)&igFocusWindow, "igFocusWindow");
			bindFunc(cast(void**)&igSetActiveID, "igSetActiveID");
			bindFunc(cast(void**)&igKeepAliveID, "igKeepAliveID");
			bindFunc(cast(void**)&igItemSize, "igItemSize");
			bindFunc(cast(void**)&igItemSize2, "igItemSize2");
			bindFunc(cast(void**)&igItemAdd, "igItemAdd");
			bindFunc(cast(void**)&igIsClippedEx, "igIsClippedEx");
			bindFunc(cast(void**)&igIsHovered, "igIsHovered");
			bindFunc(cast(void**)&igFocusableItemRegister, "igFocusableItemRegister");
			bindFunc(cast(void**)&igFocusableItemUnregister, "igFocusableItemUnregister");
			bindFunc(cast(void**)&igCalcWrapWidthForPos, "igCalcWrapWidthForPos");
			bindFunc(cast(void**)&igRenderText, "igRenderText");
			bindFunc(cast(void**)&igRenderTextWrapped, "igRenderTextWrapped");
			bindFunc(cast(void**)&igRenderTextClipped, "igRenderTextClipped");
			bindFunc(cast(void**)&igRenderFrame, "igRenderFrame");
			bindFunc(cast(void**)&igRenderCollapseTriangle, "igRenderCollapseTriangle");
			bindFunc(cast(void**)&igRenderCheckMark, "igRenderCheckMark");
			bindFunc(cast(void**)&igButtonBehavior, "igButtonBehavior");
			bindFunc(cast(void**)&igButtonEx, "igButtonEx");
			bindFunc(cast(void**)&igSliderBehavior, "igSliderBehavior");
			bindFunc(cast(void**)&igSliderFloatN, "igSliderFloatN");
			bindFunc(cast(void**)&igSliderIntN, "igSliderIntN");
			bindFunc(cast(void**)&igDragBehavior, "igDragBehavior");
			bindFunc(cast(void**)&igDragFloatN, "igDragFloatN");
			bindFunc(cast(void**)&igDragIntN, "igDragIntN");
			bindFunc(cast(void**)&igInputTextEx, "igInputTextEx");
			bindFunc(cast(void**)&igInputFloatN, "igInputFloatN");
			bindFunc(cast(void**)&igInputIntN, "igInputIntN");
			bindFunc(cast(void**)&igTreeNodeBehaviorIsOpened, "igTreeNodeBehaviorIsOpened");
			bindFunc(cast(void**)&igParseFormatPrecision, "igParseFormatPrecision");
			bindFunc(cast(void**)&igRoundScalar, "igRoundScalar");
			bindFunc(cast(void**)&igGetImGuiState, "igGetImGuiState");
			bindFunc(cast(void**)&igGetSkipItems, "igGetSkipItems");
        }
    }

    public
    {
        this()
        {
            super(libNames);
        }
    }
}

__gshared DerelictImguiLoader DerelictImgui;

shared static this()
{
    DerelictImgui = new DerelictImguiLoader();
}
