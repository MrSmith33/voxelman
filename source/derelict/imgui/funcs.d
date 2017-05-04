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
module derelict.imgui.funcs;

private
{
    import derelict.imgui.types;
    import core.stdc.stdarg:va_list;
}

extern(C) @nogc nothrow
{
	ImGuiIO* igGetIO();
	ImGuiStyle* igGetStyle();
	ImDrawData* igGetDrawData();
	void igNewFrame();
	void igRender();
	void igShutdown();
	void igShowUserGuide();
	void igShowStyleEditor(ImGuiStyle* ref_);
	void igShowTestWindow(bool* opened = null);
	void igShowMetricsWindow(bool* opened = null);

    // Window
	bool igBegin(const char* name, bool* p_opened = null, ImGuiWindowFlags flags = 0);
	bool igBegin2(const char* name, bool* p_opened, const ImVec2 size_on_first_use, float bg_alpha = -1.0f, ImGuiWindowFlags flags = 0);
	void igEnd();
	bool igBeginChild(const char* str_id, const ImVec2 size = ImVec2(0, 0), bool border = false, ImGuiWindowFlags extra_flags = 0);
	bool igBeginChildEx(ImGuiID id, const ImVec2 size = ImVec2(0, 0), bool border = false, ImGuiWindowFlags extra_flags = 0);
	void igEndChild();
	void igGetContentRegionMax(ImVec2* outParam);
	void igGetContentRegionAvail(ImVec2* outParam);
	float igGetContentRegionAvailWidth();
	void igGetWindowContentRegionMin(ImVec2* outParam);
	void igGetWindowContentRegionMax(ImVec2* outParam);
	float igGetWindowContentRegionWidth();
	ImDrawList* igGetWindowDrawList();
	ImFont* igGetWindowFont();
	float igGetWindowFontSize();
	void igSetWindowFontScale(float scale);
	void igGetWindowPos(ImVec2* outParam);
	void igGetWindowSize(ImVec2* outParam);
	float igGetWindowWidth();
	float igGetWindowHeight();
	bool igIsWindowCollapsed();
	void igSetNextWindowPos(const ImVec2 pos, ImGuiSetCond cond = 0);
	void igSetNextWindowPosCenter(ImGuiSetCond cond = 0);
	void igSetNextWindowSize(const ImVec2 size, ImGuiSetCond cond = 0);
	void igSetNextWindowCollapsed(bool collapsed, ImGuiSetCond cond = 0);
	void igSetNextWindowFocus();
	void igSetWindowPos(const ImVec2 pos, ImGuiSetCond cond = 0);
	void igSetWindowSize(const ImVec2 size, ImGuiSetCond cond = 0);
	void igSetNextWindowContentSize(const ImVec2 size);
	void igSetNextWindowContentWidth(float width);
	void igSetWindowCollapsed(bool collapsed, ImGuiSetCond cond = 0);
	void igSetWindowFocus();
	void igSetWindowPosByName(const char* name, const ImVec2 pos, ImGuiSetCond cond = 0);
	void igSetWindowSize2(const char* name, const ImVec2 size, ImGuiSetCond cond = 0);
	void igSetWindowCollapsed2(const char* name, bool collapsed, ImGuiSetCond cond = 0);
	void igSetWindowFocus2(const char* name);
	float igGetScrollX();
	float igGetScrollY();
	float igGetScrollMaxX();
	float igGetScrollMaxY();
	void igSetScrollX(int scroll_x);
	void igSetScrollY(int scroll_y);
	void igSetScrollHere(float center_y_ratio = 0.5f);
	void igSetScrollFromPosY(float pos_y, float center_y_ratio = 0.5f);
	void igSetKeyboardFocusHere(int offset = 0);
	void igSetStateStorage(ImGuiStorage* tree);
	ImGuiStorage* igGetStateStorage();
	void igPushFont(ImFont* font);
	void igPopFont();
	void igPushStyleColor(ImGuiCol idx, const ImVec4 col);
	void igPopStyleColor(int count = 1);
	void igPushStyleVar(ImGuiStyleVar idx, float val);
	void igPushStyleVarVec(ImGuiStyleVar idx, const ImVec2 val);
	void igPopStyleVar(int count = 1);
	void igPushItemWidth(float item_width);
	void igPopItemWidth();
	float igCalcItemWidth();
	void igPushAllowKeyboardFocus(bool v);
	void igPopAllowKeyboardFocus();
	void igPushTextWrapPos(float wrap_pos_x = 0.0f);
	void igPopTextWrapPos();
	void igPushButtonRepeat(bool repeat);
	void igPopButtonRepeat();
	void igBeginGroup();
	void igEndGroup();
	void igSeparator();
	void igSameLine(float local_pos_x = 0.0f, float spacing_w = -1.0f);
	void igSpacing();
	void igDummy(const ImVec2* size);
	void igIndent();
	void igUnindent();
	void igColumns(int count = 1, const char* id = null, bool border = true);
	void igNextColumn();
	int igGetColumnIndex();
	float igGetColumnOffset(int column_index = -1);
	void igSetColumnOffset(int column_index, float offset_x);
	float igGetColumnWidth(int column_index = -1);
	int igGetColumnsCount();
	void igGetCursorPos(ImVec2* pOut);
	float igGetCursorPosX();
	float igGetCursorPosY();
	void igSetCursorPos(const ImVec2 locl_pos);
	void igSetCursorPosX(float x);
	void igSetCursorPosY(float y);
	void igGetCursorStartPos(ImVec2* pOut);
	void igGetCursorScreenPos(ImVec2* pOut);
	void igSetCursorScreenPos(const ImVec2 pos);
	void igAlignFirstTextHeightToWidgets();
	float igGetTextLineHeight();
	float igGetTextLineHeightWithSpacing();
	float igGetItemsLineHeightWithSpacing();
	void igPushIdStr(const char* str_id);
	void igPushIdStrRange(const char* str_begin, const char* str_end);
	void igPushIdPtr(const void* ptr_id);
	void igPushIdInt(int int_id);
	void igPopId();
	ImGuiID igGetIdStr(const char* str_id);
	ImGuiID igGetIdStrRange(const char* str_begin, const char* str_end);
	ImGuiID igGetIdPtr(const void* ptr_id);
	void igText(const char* fmt, ...);
	void igTextV(const char* fmt, va_list args);
	void igTextColored(const ImVec4 col, const char* fmt, ...);
	void igTextColoredV(const ImVec4 col, const char* fmt, va_list args);
	void igTextDisabled(const char* fmt, ...);
	void igTextDisabledV(const char* fmt, va_list args);
	void igTextWrapped(const char* fmt, ...);
	void igTextWrappedV(const char* fmt, va_list args);
	void igTextUnformatted(const char* text, const char* text_end = null);
	void igLabelText(const char* label, const char* fmt, ...);
	void igLabelTextV(const char* label, const char* fmt, va_list args);
	void igBullet();
	void igBulletText(const char* fmt, ...);
	void igBulletTextV(const char* fmt, va_list args);
	bool igButton(const char* label, const ImVec2 size = ImVec2(0, 0));
	bool igSmallButton(const char* label);
	bool igInvisibleButton(const char* str_id, const ImVec2 size);
	void igImage(ImTextureID user_texture_id, const ImVec2 size, const ImVec2 uv0 = ImVec2(0, 0), const ImVec2 uv1 = ImVec2(1, 1), const ImVec4 tint_col = ImVec4(1, 1, 1, 1), const ImVec4 border_col = ImVec4(0, 0, 0, 0));
	bool igImageButton(ImTextureID user_texture_id, const ImVec2 size, const ImVec2 uv0 = ImVec2(0, 0), const ImVec2 uv1 = ImVec2(1, 1), int frame_padding = -1, const ImVec4 bg_col = ImVec4(0, 0, 0, 0), const ImVec4 tint_col = ImVec4(1, 1, 1, 1));
	bool igCollapsingHeader(const char* label, const char* str_id = null, bool display_frame = true, bool default_open = false);
	bool igCheckbox(const char* label, bool* v);
	bool igCheckboxFlags(const char* label, uint* flags, uint flags_value);
	bool igRadioButtonBool(const char* label, bool active);
	bool igRadioButton(const char* label, int* v, int v_button);
	bool igCombo(const char* label, int* current_item, const char** items, int items_count, int height_in_items = -1);
	bool igCombo2(const char* label, int* current_item, const char* items_separated_by_zeros, int height_in_items = -1);
	bool igCombo3(const char* label, int* current_item, bool function(void* data, int idx, const(char)** out_text) items_getter, void* data, int items_count, int height_in_items = -1);
	bool igColorButton(const ImVec4 col, bool small_height = false, bool outline_border = true);
	bool igColorEdit3(const char* label, ref float[3] col);
	bool igColorEdit4(const char* label, ref float[4] col, bool show_alpha = true);
	void igColorEditMode(ImGuiColorEditMode mode);
	void igPlotLines(const char* label, const float* values, int values_count, int values_offset = 0, const char* overlay_text = null, float scale_min = float.max, float scale_max = float.max, ImVec2 graph_size = ImVec2(0, 0), size_t stride = float.sizeof);
	void igPlotLines2(const char* label, float function(void* data, int idx) values_getter, void* data, int values_count, int values_offset = 0, const char* overlay_text = null, float scale_min = float.max, float scale_max = float.max, ImVec2 graph_size = ImVec2(0, 0));
	void igPlotHistogram(const char* label, const float* values, int values_count, int values_offset = 0, const char* overlay_text = null, float scale_min = float.max, float scale_max = float.max, ImVec2 graph_size = ImVec2(0, 0), size_t stride = float.sizeof);
	void igPlotHistogram2(const char* label, float function(void* data, int idx) values_getter, void* data, int values_count, int values_offset = 0, const char* overlay_text = null, float scale_min = float.max, float scale_max = float.max, ImVec2 graph_size = ImVec2(0, 0));
	bool igSliderFloat(const char* label, float* v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
	bool igSliderFloat2(const char* label, ref float[2] v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
	bool igSliderFloat3(const char* label, ref float[3] v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
	bool igSliderFloat4(const char* label, ref float[4] v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
	bool igSliderAngle(const char* label, float* v_rad, float v_degrees_min = -360.0f, float v_degrees_max = +360.0f);
	bool igSliderInt(const char* label, int* v, int v_min, int v_max, const char* display_format = "%.0f");
	bool igSliderInt2(const char* label, ref int[2] v, int v_min, int v_max, const char* display_format = "%.0f");
	bool igSliderInt3(const char* label, ref int[3] v, int v_min, int v_max, const char* display_format = "%.0f");
	bool igSliderInt4(const char* label, ref int[4] v, int v_min, int v_max, const char* display_format = "%.0f");
	bool igVSliderFloat(const char* label, const ImVec2 size, float* v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
	bool igVSliderInt(const char* label, const ImVec2 size, int* v, int v_min, int v_max, const char* display_format = "%.0f");
	bool igDragFloat(const char* label, float* v, float v_speed = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f", float power = 1.0f);     // If v_max >= v_max we have no bound
	bool igDragFloat2(const char* label, ref float[2] v, float v_speed = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f", float power = 1.0f);
	bool igDragFloat3(const char* label, ref float[3] v, float v_speed = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f", float power = 1.0f);
	bool igDragFloat4(const char* label, ref float[4] v, float v_speed = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f", float power = 1.0f);
	bool igDragFloatRange2(const char* label, float* v_current_min, float* v_current_max, float v_speed = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f", const char* display_format_max = null, float power = 1.0f);
	bool igDragInt(const char* label, int* v, float v_speed = 1.0f, int v_min = 0, int v_max = 0, const char* display_format = "%.3f");                                       // If v_max >= v_max we have no bound
	bool igDragInt2(const char* label, ref int[2] v, float v_speed = 1.0f, int v_min = 0, int v_max = 0, const char* display_format = "%.3f");
	bool igDragInt3(const char* label, ref int[3] v, float v_speed = 1.0f, int v_min = 0, int v_max = 0, const char* display_format = "%.3f");
	bool igDragInt4(const char* label, ref int[4] v, float v_speed = 1.0f, int v_min = 0, int v_max = 0, const char* display_format = "%.3f");
	bool igDragIntRange2(const char* label, int* v_current_min, int* v_current_max, float v_speed = 1.0f, int v_min = 0, int v_max = 0, const char* display_format = "%.0f", const char* display_format_max = null);
	bool igInputText(const char* label, char* buf, size_t buf_size, ImGuiInputTextFlags flags = 0, ImGuiTextEditCallback callback = null, void* user_data = null);
	bool igInputTextMultiline(const char* label, char* buf, size_t buf_size, const ImVec2 size = ImVec2(0,0), ImGuiInputTextFlags flags = 0, ImGuiTextEditCallback callback = null, void* user_data = null);
	bool igInputFloat(const char* label, float* v, float step = 0.0f, float step_fast = 0.0f, int decimal_precision = -1, ImGuiInputTextFlags extra_flags = 0);
	bool igInputFloat2(const char* label, ref float[2] v, int decimal_precision = -1, ImGuiInputTextFlags extra_flags = 0);
	bool igInputFloat3(const char* label, ref float[3] v, int decimal_precision = -1, ImGuiInputTextFlags extra_flags = 0);
	bool igInputFloat4(const char* label, ref float[4] v, int decimal_precision = -1, ImGuiInputTextFlags extra_flags = 0);
	bool igInputInt(const char* label, int* v, int step = 1, int step_fast = 100, ImGuiInputTextFlags extra_flags = 0);
	bool igInputInt2(const char* label, ref int[2] v, ImGuiInputTextFlags extra_flags = 0);
	bool igInputInt3(const char* label, ref int[3] v, ImGuiInputTextFlags extra_flags = 0);
	bool igInputInt4(const char* label, ref int[4] v, ImGuiInputTextFlags extra_flags = 0);
	bool igTreeNode(const char* str_label_id);
	bool igTreeNodeStr(const char* str_id, const char* fmt, ...);
	bool igTreeNodePtr(const void* ptr_id, const char* fmt, ...);
	bool igTreeNodeStrV(const char* str_id, const char* fmt, va_list args);
	bool igTreeNodePtrV(const void* ptr_id, const char* fmt, va_list args);
	void igTreePushStr(const char* str_id = null);
	void igTreePushPtr(const void* ptr_id = null);
	void igTreePop();
	void igSetNextTreeNodeOpened(bool opened, ImGuiSetCond cond = 0);
	bool igSelectable(const char* label, bool selected = false, ImGuiSelectableFlags flags = 0, const ImVec2 size = ImVec2(0, 0));
	bool igSelectableEx(const char* label, bool* p_selected, ImGuiSelectableFlags flags = 0, const ImVec2 size = ImVec2(0, 0));
	bool igListBox(const char* label, int* current_item, const char** items, int items_count, int height_in_items = -1);
	bool igListBox2(const char* label, int* current_item, bool function(void* data, int idx, const char** out_text) items_getter, void* data, int items_count, int height_in_items = -1);
	bool igListBoxHeader(const char* label, const ImVec2 size = ImVec2(0, 0));
	bool igListBoxHeader2(const char* label, int items_count, int height_in_items = -1);
	void igListBoxFooter();
	void igValueBool(const char* prefix, bool b);
	void igValueInt(const char* prefix, int v);
	void igValueUInt(const char* prefix, uint v);
	void igValueFloat(const char* prefix, float v, const char* float_format = null);
	void igValueColor(const char* prefix, const ImVec4 v);
	void igValueColor2(const char* prefix, uint v);
	void igSetTooltip(const(char)* fmt, ...);
	void igSetTooltipV(const(char)* fmt, va_list args);
	void igBeginTooltip();
	void igEndTooltip();

    // Widgets: Menus
	bool igBeginMainMenuBar();
	void igEndMainMenuBar();
	bool igBeginMenuBar();
	void igEndMenuBar();
	bool igBeginMenu(const(char)* label, bool enabled = true);
	void igEndMenu();
	bool igMenuItem(const(char)* label, const(char)* shortcut, bool selected = false, bool enabled = true);
	bool igMenuItemPtr(const(char)* label, const(char)* shortcut, bool* p_selected, bool enabled = true);
	void igOpenPopup(const(char)* str_id);
	bool igBeginPopup(const(char)* str_id);
	bool igBeginPopupModal(const(char)* name, bool* p_opened = null, ImGuiWindowFlags extra_flags = 0);
	bool igBeginPopupContextItem(const(char)* str_id, int mouse_button = 1);
	bool igBeginPopupContextWindow(bool also_over_items = true, const(char)* str_id = null, int mouse_button = 1);
	bool igBeginPopupContextVoid(const char* str_id = null, int mouse_button = 1);
	void igEndPopup();
	void igCloseCurrentPopup();
	void igLogToTTY(int max_depth = -1);
	void igLogToFile(int max_depth = -1, const char* filename = null);
	void igLogToClipboard(int max_depth = -1);
	void igLogFinish();
	void igLogButtons();
	void igLogText(const char* fmt, ...);
	bool igIsItemHovered();
	bool igIsItemHoveredRect();
	bool igIsItemActive();
	bool igIsItemVisible();
	bool igIsAnyItemHovered();
	bool igIsAnyItemActive();
	void igGetItemRectMin(ImVec2* pOut);
	void igGetItemRectMax(ImVec2* pOut);
	void igGetItemRectSize(ImVec2* pOut);
	bool igIsWindowHovered();
	bool igIsWindowFocused();
	bool igIsRootWindowFocused();
	bool igIsRootWindowOrAnyChildFocused();
	bool igIsRectVisible(const ImVec2 item_size);
	bool igIsKeyDown(int key_index);
	bool igIsKeyPressed(int key_index, bool repeat = true);
	bool igIsKeyReleased(int key_index);
	bool igIsMouseDown(int button);
	bool igIsMouseClicked(int button, bool repeat = false);
	bool igIsMouseDoubleClicked(int button);
	bool igIsMouseReleased(int button);
	bool igIsMouseHoveringWindow();
	bool igIsMouseHoveringAnyWindow();
	bool igIsMouseHoveringRect(const ImVec2 pos_min, const ImVec2 pos_max, bool clip = true);
	bool igIsMouseDragging(int button = 0, float lock_threshold = -1.0f);
	bool igIsPosHoveringAnyWindow(const ImVec2 pos);
	void igGetMousePos(ImVec2* pOut);
	void igGetMousePosOnOpeningCurrentPopup(ImVec2* pOut);
	void igGetMouseDragDelta(ImVec2* pOut, int button = 0, float lock_threshold = -1.0f);
	void igResetMouseDragDelta(int button=0);
	ImGuiMouseCursor igGetMouseCursor();
	void igSetMouseCursor(ImGuiMouseCursor type);
	void igCaptureKeyboardFromApp();
	void igCaptureMouseFromApp();
	void* igMemAlloc(size_t sz);
	void igMemFree(void* ptr);
	const(char)* igGetClipboardText();
	void igSetClipboardText(const(char)* text);
	float igGetTime();
	int igGetFrameCount();
	const(char)* igGetStyleColName(ImGuiCol idx);
	void igCalcItemRectClosestPoint(ImVec2* pOut, const ImVec2 pos, bool on_edge = false, float outward = +0.0f);
	void igCalcTextSize(ImVec2* pOut, const char* text, const char* text_end = null, bool hide_text_after_double_hash = false, float wrap_width = -1.0f);
	void igCalcListClipping(int items_count, float items_height, int* out_items_display_start, int* out_items_display_end);
	bool igBeginChildFrame(ImGuiID id, const ImVec2 size, ImGuiWindowFlags extra_flags = 0);
	void igEndChildFrame();
	void igColorConvertU32ToFloat4(ImVec4* pOut, ImU32 in_);
	ImU32 igColorConvertFloat4ToU32(const ImVec4 in_);
	void igColorConvertRGBtoHSV(float r, float g, float b, float* out_h, float* out_s, float* out_v);
	void igColorConvertHSVtoRGB(float h, float s, float v, float* out_r, float* out_g, float* out_b);
	const(char)* igGetVersion();
	void* igGetInternalState();
	size_t igGetInternalStateSize();
	void igSetInternalState(void* state, bool con= false);
}

// ImFontAtlas Methods
extern(C) @nogc nothrow
{
	void ImFontAtlas_GetTexDataAsRGBA32(ImFontAtlas* atlas,ubyte** out_pixels,int* out_width,int* out_height,int* out_bytes_per_pixel);
	void ImFontAtlas_GetTexDataAsAlpha8(ImFontAtlas* atlas,ubyte** out_pixels,int* out_width,int* out_height,int* out_bytes_per_pixel);
	void ImFontAtlas_SetTexID(ImFontAtlas* atlas, void* id);
	ImFont* ImFontAtlas_AddFont(ImFontAtlas* atlas, const ImFontConfig* font_cfg);
	ImFont* ImFontAtlas_AddFontDefault(ImFontAtlas* atlas, const ImFontConfig* font_cfg);
	ImFont* ImFontAtlas_AddFontFromFileTTF(ImFontAtlas* atlas, const char* filename, float size_pixels, const ImFontConfig* font_cfg, const ImWchar* glyph_ranges = null);
	ImFont* ImFontAtlas_AddFontFromMemoryTTF(ImFontAtlas* atlas, void* ttf_data, int ttf_size, float size_pixels, const ImFontConfig* font_cfg, const ImWchar* glyph_ranges = null);
	ImFont* ImFontAtlas_AddFontFromMemoryCompressedTTF(ImFontAtlas* atlas, const void* compressed_ttf_data, int compressed_ttf_size, float size_pixels, const ImFontConfig* font_cfg = null, const ImWchar* glyph_ranges = null);
	ImFont* ImFontAtlas_AddFontFromMemoryCompressedBase85TTF(ImFontAtlas* atlas, const char* compressed_ttf_data_base85, float size_pixels, const ImFontConfig* font_cfg = null, const ImWchar* glyph_ranges = null);
	void ImFontAtlas_ClearTexData(ImFontAtlas* atlas, void* id);
	void ImFontAtlas_Clear(ImFontAtlas* atlas, void* id);
}

//TODO: rework
extern(C) @nogc nothrow
{
	int ImDrawList_GetVertexBufferSize(ImDrawList* list);
	ImDrawVert* ImDrawList_GetVertexPtr(ImDrawList* list, int n);
	int ImDrawList_GetIndexBufferSize(ImDrawList* list);
	ImDrawIdx* ImDrawList_GetIndexPtr(ImDrawList* list, int n);
	int ImDrawList_GetCmdSize(ImDrawList* list);
	ImDrawCmd* ImDrawList_GetCmdPtr(ImDrawList* list, int n);
	void ImDrawData_DeIndexAllBuffers(ImDrawData* drawData);
	void ImGuiIO_AddInputCharacter(ushort c);
	void ImGuiIO_AddInputCharactersUTF8(const(char*) utf8_chars);
	void ImDrawList_Clear(ImDrawList* list);
	void ImDrawList_ClearFreeMemory(ImDrawList* list);
	void ImDrawList_PushClipRect(ImDrawList* list, const ImVec4 clip_rect);
	void ImDrawList_PushClipRectFullScreen(ImDrawList* list);
	void ImDrawList_PopClipRect(ImDrawList* list);
	void ImDrawList_PushTextureID(ImDrawList* list, const ImTextureID texture_id);
	void ImDrawList_PopTextureID(ImDrawList* list);
	void ImDrawList_AddLine(ImDrawList* list, const ImVec2 a, const ImVec2 b, ImU32 col, float thickness = 1.0f);
	void ImDrawList_AddRect(ImDrawList* list, const ImVec2 a, const ImVec2 b, ImU32 col, float rounding = 0.0f, int rounding_corners = 0x0F);
	void ImDrawList_AddRectFilled(ImDrawList* list, const ImVec2 a, const ImVec2 b, ImU32 col, float rounding = 0.0f, int rounding_corners = 0x0F);
	void ImDrawList_AddRectFilledMultiColor(ImDrawList* list, const ImVec2 a, const ImVec2 b, ImU32 col_upr_left, ImU32 col_upr_right, ImU32 col_bot_right, ImU32 col_bot_left);
	void ImDrawList_AddTriangleFilled(ImDrawList* list, const ImVec2 a, const ImVec2 b, const ImVec2 c, ImU32 col);
	void ImDrawList_AddCircle(ImDrawList* list, const ImVec2 centre, float radius, ImU32 col, int num_segments = 12);
	void ImDrawList_AddCircleFilled(ImDrawList* list, const ImVec2 centre, float radius, ImU32 col, int num_segments = 12);
	void ImDrawList_AddText(ImDrawList* list, const ImVec2 pos, ImU32 col, const char* text_begin, const char* text_end = null);
	void ImDrawList_AddTextExt(ImDrawList* list, const ImFont* font, float font_size, const ImVec2 pos, ImU32 col, const char* text_begin, const char* text_end = null, float wrap_width = 0.0f, const ImVec4* cpu_fine_clip_rect = null);
	void ImDrawList_AddImage(ImDrawList* list, ImTextureID user_texture_id, const ImVec2 a, const ImVec2 b, const ImVec2 uv0, const ImVec2 uv1, ImU32 col = 0xFFFFFFFF);
	void ImDrawList_AddPolyline(ImDrawList* list, const ImVec2* points, const int num_points, ImU32 col, bool closed, float thickness, bool anti_aliased);
	void ImDrawList_AddConvexPolyFilled(ImDrawList* list, const ImVec2* points, const int num_points, ImU32 col, bool anti_aliased);
	void ImDrawList_AddBezierCurve(ImDrawList* list, const ImVec2 pos0, const ImVec2 cp0, const ImVec2 cp1, const ImVec2 pos1, ImU32 col, float thickness, int num_segments = 0);
	void ImDrawList_PathClear(ImDrawList* list);
	void ImDrawList_PathLineTo(ImDrawList* list, const ImVec2 pos);
	void ImDrawList_PathLineToMergeDuplicate(ImDrawList* list, const ImVec2 pos);
	void ImDrawList_PathFill(ImDrawList* list, ImU32 col);
	void ImDrawList_PathStroke(ImDrawList* list, ImU32 col, bool closed, float thickness = 1.0f);
	void ImDrawList_PathArcTo(ImDrawList* list, const ImVec2 centre, float radius, float a_min, float a_max, int num_segments = 10);
	void ImDrawList_PathArcToFast(ImDrawList* list, const ImVec2 centre, float radius, int a_min_of_12, int a_max_of_12);
	void ImDrawList_PathBezierCurveTo(ImDrawList* list, const ImVec2 p1, const ImVec2 p2, const ImVec2 p3, int num_segments = 0);
	void ImDrawList_PathRect(ImDrawList* list, const ImVec2 rect_min, const ImVec2 rect_max, float rounding = 0.0f, int rounding_corners = 0x0F);
	void ImDrawList_ChannelsSplit(ImDrawList* list, int channels_count);
	void ImDrawList_ChannelsMerge(ImDrawList* list);
	void ImDrawList_ChannelsSetCurrent(ImDrawList* list, int channel_index);
	void ImDrawList_AddCallback(ImDrawList* list, ImDrawCallback callback, void* callback_data);
	void ImDrawList_AddDrawCmd(ImDrawList* list);
	void ImDrawList_PrimReserve(ImDrawList* list, int idx_count, int vtx_count);
	void ImDrawList_PrimRect(ImDrawList* list, const ImVec2 a, const ImVec2 b, ImU32 col);
	void ImDrawList_PrimRectUV(ImDrawList* list, const ImVec2 a, const ImVec2 b, const ImVec2 uv_a, const ImVec2 uv_b, ImU32 col);
	void ImDrawList_PrimVtx(ImDrawList* list, const ImVec2 pos, const ImVec2 uv, ImU32 col);
	void ImDrawList_PrimWriteVtx(ImDrawList* list, const ImVec2 pos, const ImVec2 uv, ImU32 col);
	void ImDrawList_PrimWriteIdx(ImDrawList* list, ImDrawIdx idx);
	void ImDrawList_UpdateClipRect(ImDrawList* list);
	void ImDrawList_UpdateTextureID(ImDrawList* list);

	//-----------------------------------------------------------------------------
	// Internal API
	// No guarantee of forward compatibility here.
	ImGuiWindow* igGetCurrentWindowRead();
	ImGuiWindow* igGetCurrentWindow();
	ImGuiWindow* igGetParentWindow();
	void igFocusWindow(ImGuiWindow* window);
	void igSetActiveID(ImGuiID id, ImGuiWindow* window);
	void igKeepAliveID(ImGuiID id);
	void igItemSize(const ImVec2 size, float text_offset_y = 0.0f);
	void igItemSize2(const ImRect bb, float text_offset_y = 0.0f);
	bool igItemAdd(const ImRect bb, const ImGuiID* id);
	bool igIsClippedEx(const ImRect bb, const ImGuiID* id, bool clip_even_when_logged);
	bool igIsHovered(const ImRect bb, ImGuiID id, bool flatten_childs = false);
	bool igFocusableItemRegister(ImGuiWindow* window, bool is_active, bool tab_stop = true);
	void igFocusableItemUnregister(ImGuiWindow* window);
	float igCalcWrapWidthForPos(const ImVec2 pos, float wrap_pos_x);
	void igRenderText(ImVec2 pos, const char* text, const char* text_end = null, bool hide_text_after_hash = true);
	void igRenderTextWrapped(ImVec2 pos, const char* text, const char* text_end, float wrap_width);
	void igRenderTextClipped(const ImVec2 pos_min, const ImVec2 pos_max, const char* text, const char* text_end, const ImVec2* text_size_if_known, ImGuiAlign align_ = ImGuiAlign_Default, const ImVec2* clip_min = null, const ImVec2* clip_max = null);
	void igRenderFrame(ImVec2 p_min, ImVec2 p_max, ImU32 fill_col, bool border = true, float rounding = 0.0f);
	void igRenderCollapseTriangle(ImVec2 p_min, bool opened, float scale = 1.0f, bool shadow = false);
	void igRenderCheckMark(ImVec2 pos, ImU32 col);
	bool igButtonBehavior(const ImRect bb, ImGuiID id, bool* out_hovered, bool* out_held, ImGuiButtonFlags flags = 0);
	bool igButtonEx(const char* label, const ImVec2 size_arg = ImVec2(0, 0), ImGuiButtonFlags flags = 0);
	bool igSliderBehavior(const ImRect frame_bb, ImGuiID id, float* v, float v_min, float v_max, float power, int decimal_precision, bool horizontal);
	bool igSliderFloatN(const char* label, float* v, int components, float v_min, float v_max, const char* display_format, float power);
	bool igSliderIntN(const char* label, int* v, int components, int v_min, int v_max, const char* display_format);
	bool igDragBehavior(const ImRect frame_bb, ImGuiID id, float* v, float v_speed, float v_min, float v_max, int decimal_precision, float power);
	bool igDragFloatN(const char* label, float* v, int components, float v_speed, float v_min, float v_max, const char* display_format, float power);
	bool igDragIntN(const char* label, int* v, int components, float v_speed, int v_min, int v_max, const char* display_format);
	bool igInputTextEx(const char* label, char* buf, int buf_size, const ImVec2 size_arg, ImGuiInputTextFlags flags, ImGuiTextEditCallback callback = null, void* user_data = null);
	bool igInputFloatN(const char* label, float* v, int components, int decimal_precision, ImGuiInputTextFlags extra_flags);
	bool igInputIntN(const char* label, int* v, int components, ImGuiInputTextFlags extra_flags);
	bool igTreeNodeBehaviorIsOpened(ImGuiID id, ImGuiTreeNodeFlags flags = 0);
	int igParseFormatPrecision(const char* fmt, int default_value);
	float igRoundScalar(float value, int decimal_precision);
	ImGuiState* igGetImGuiState();
	bool igGetSkipItems(ImGuiWindow* window);

	// namespace ImGuiP
}
