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
module derelict.imgui.types;

import derelict.util.system;

enum
{
    ImGuiKey_Tab,       // for tabbing through fields
    ImGuiKey_LeftArrow, // for text edit
    ImGuiKey_RightArrow,// for text edit
    ImGuiKey_UpArrow,   // for text edit
    ImGuiKey_DownArrow, // for text edit
    ImGuiKey_PageUp,
    ImGuiKey_PageDown,
    ImGuiKey_Home,      // for text edit
    ImGuiKey_End,       // for text edit
    ImGuiKey_Delete,    // for text edit
    ImGuiKey_Backspace, // for text edit
    ImGuiKey_Enter,     // for text edit
    ImGuiKey_Escape,    // for text edit
    ImGuiKey_A,         // for text edit CTRL+A: select all
    ImGuiKey_C,         // for text edit CTRL+C: copy
    ImGuiKey_V,         // for text edit CTRL+V: paste
    ImGuiKey_X,         // for text edit CTRL+X: cut
    ImGuiKey_Y,         // for text edit CTRL+Y: redo
    ImGuiKey_Z,         // for text edit CTRL+Z: undo
	ImGuiKey_COUNT
};

enum
{
    // Default: 0
    ImGuiWindowFlags_NoTitleBar             = 1 << 0,   // Disable title-bar
    ImGuiWindowFlags_NoResize               = 1 << 1,   // Disable user resizing with the lower-right grip
    ImGuiWindowFlags_NoMove                 = 1 << 2,   // Disable user moving the window
    ImGuiWindowFlags_NoScrollbar            = 1 << 3,   // Disable scrollbar (window can still scroll with mouse or programatically)
    ImGuiWindowFlags_NoScrollWithMouse      = 1 << 4,   // Disable user scrolling with mouse wheel
    ImGuiWindowFlags_NoCollapse             = 1 << 5,   // Disable user collapsing window by double-clicking on it
    ImGuiWindowFlags_AlwaysAutoResize       = 1 << 6,   // Resize every window to its content every frame
    ImGuiWindowFlags_ShowBorders            = 1 << 7,   // Show borders around windows and items
    ImGuiWindowFlags_NoSavedSettings        = 1 << 8,   // Never load/save settings in .ini file
	ImGuiWindowFlags_NoInputs               = 1 << 9,   // Disable catching mouse or keyboard inputs
    ImGuiWindowFlags_MenuBar                = 1 << 10,   // Has a menubar
    ImGuiWindowFlags_HorizontalScrollbar    = 1 << 11,  // Enable horizontal scrollbar (off by default). You need to use SetNextWindowContentSize(ImVec2(width,0.0f)); prior to calling Begin() to specify width. Read code in imgui_demo in the "Horizontal Scrolling" section.
    ImGuiWindowFlags_NoFocusOnAppearing     = 1 << 12,  // Disable taking focus when transitioning from hidden to visible state
    ImGuiWindowFlags_NoBringToFrontOnFocus  = 1 << 13,  // Disable bringing window to front when taking focus (e.g. clicking on it or programatically giving it focus)
    // [Internal]
    ImGuiWindowFlags_ChildWindow            = 1 << 20,  // Don't use! For internal use by BeginChild()
    ImGuiWindowFlags_ChildWindowAutoFitX    = 1 << 21,  // Don't use! For internal use by BeginChild()
    ImGuiWindowFlags_ChildWindowAutoFitY    = 1 << 22,  // Don't use! For internal use by BeginChild()
    ImGuiWindowFlags_ComboBox               = 1 << 23,  // Don't use! For internal use by ComboBox()
    ImGuiWindowFlags_Tooltip                = 1 << 24,  // Don't use! For internal use by BeginTooltip()
    ImGuiWindowFlags_Popup                  = 1 << 25,  // Don't use! For internal use by BeginPopup()
    ImGuiWindowFlags_Modal                  = 1 << 26,  // Don't use! For internal use by BeginPopupModal()
    ImGuiWindowFlags_ChildMenu              = 1 << 27   // Don't use! For internal use by BeginMenu()
}

enum
{
    // Default: 0
    ImGuiInputTextFlags_CharsDecimal        = 1 << 0,   // Allow 0123456789.+-*/
    ImGuiInputTextFlags_CharsHexadecimal    = 1 << 1,   // Allow 0123456789ABCDEFabcdef
    ImGuiInputTextFlags_CharsUppercase      = 1 << 2,   // Turn a..z into A..Z
    ImGuiInputTextFlags_CharsNoBlank        = 1 << 3,   // Filter out spaces, tabs
    ImGuiInputTextFlags_AutoSelectAll       = 1 << 4,   // Select entire text when first taking mouse focus
    ImGuiInputTextFlags_EnterReturnsTrue    = 1 << 5,   // Return 'true' when Enter is pressed (as opposed to when the value was modified)
    ImGuiInputTextFlags_CallbackCompletion  = 1 << 6,   // Call user function on pressing TAB (for completion handling)
    ImGuiInputTextFlags_CallbackHistory     = 1 << 7,   // Call user function on pressing Up/Down arrows (for history handling)
    ImGuiInputTextFlags_CallbackAlways      = 1 << 8,   // Call user function every time
    ImGuiInputTextFlags_CallbackCharFilter  = 1 << 9,   // Call user function to filter character. Modify data->EventChar to replace/filter input, or return 1 to discard character.
    ImGuiInputTextFlags_AllowTabInput       = 1 << 10,  // Pressing TAB input a '\t' character into the text field
    ImGuiInputTextFlags_CtrlEnterForNewLine = 1 << 11,  // In multi-line mode, allow exiting edition by pressing Enter. Ctrl+Enter to add new line (by default adds new lines with Enter).
    ImGuiInputTextFlags_NoHorizontalScroll  = 1 << 12,  // Disable following the cursor horizontally
    ImGuiInputTextFlags_AlwaysInsertMode    = 1 << 13,  // Insert mode
    ImGuiInputTextFlags_ReadOnly            = 1 << 14,  // Read-only mode
    // [Internal]
    ImGuiInputTextFlags_Multiline           = 1 << 20   // For internal use by InputTextMultiline()
}

enum
{
    // Default: 0
    ImGuiSelectableFlags_DontClosePopups    = 1 << 0,   // Clicking this don't close parent popup window
    ImGuiSelectableFlags_SpanAllColumns     = 1 << 1    // Selectable frame can span all columns (text will still fit in current column)
}

enum
{
    ImGuiSetCond_Always        = 1 << 0, // Set the variable
    ImGuiSetCond_Once          = 1 << 1, // Only set the variable on the first call per runtime session
    ImGuiSetCond_FirstUseEver  = 1 << 2, // Only set the variable if the window doesn't exist in the .ini file
    ImGuiSetCond_Appearing     = 1 << 3  // Only set the variable if the window is appearing after being inactive (or the first time)
}

enum
{
    ImGuiCol_Text,
    ImGuiCol_TextDisabled,
    ImGuiCol_WindowBg,
    ImGuiCol_ChildWindowBg,
    ImGuiCol_Border,
    ImGuiCol_BorderShadow,
    ImGuiCol_FrameBg,               // Background of checkbox, radio button, plot, slider, text input
    ImGuiCol_FrameBgHovered,
    ImGuiCol_FrameBgActive,
    ImGuiCol_TitleBg,
    ImGuiCol_TitleBgCollapsed,
    ImGuiCol_TitleBgActive,
    ImGuiCol_MenuBarBg,
    ImGuiCol_ScrollbarBg,
    ImGuiCol_ScrollbarGrab,
    ImGuiCol_ScrollbarGrabHovered,
    ImGuiCol_ScrollbarGrabActive,
    ImGuiCol_ComboBg,
    ImGuiCol_CheckMark,
    ImGuiCol_SliderGrab,
    ImGuiCol_SliderGrabActive,
    ImGuiCol_Button,
    ImGuiCol_ButtonHovered,
    ImGuiCol_ButtonActive,
    ImGuiCol_Header,
    ImGuiCol_HeaderHovered,
    ImGuiCol_HeaderActive,
    ImGuiCol_Column,
    ImGuiCol_ColumnHovered,
    ImGuiCol_ColumnActive,
    ImGuiCol_ResizeGrip,
    ImGuiCol_ResizeGripHovered,
    ImGuiCol_ResizeGripActive,
    ImGuiCol_CloseButton,
    ImGuiCol_CloseButtonHovered,
    ImGuiCol_CloseButtonActive,
    ImGuiCol_PlotLines,
    ImGuiCol_PlotLinesHovered,
    ImGuiCol_PlotHistogram,
    ImGuiCol_PlotHistogramHovered,
    ImGuiCol_TextSelectedBg,
    ImGuiCol_TooltipBg,
    ImGuiCol_ModalWindowDarkening,  // darken entire screen when a modal window is active
    ImGuiCol_COUNT
}

enum
{
	ImGuiStyleVar_Alpha,               // float
	ImGuiStyleVar_WindowPadding,       // ImVec2
	ImGuiStyleVar_WindowRounding,      // float
    ImGuiStyleVar_WindowMinSize,       // ImVec2
	ImGuiStyleVar_ChildWindowRounding, // float
	ImGuiStyleVar_FramePadding,        // ImVec2
	ImGuiStyleVar_FrameRounding,       // float
	ImGuiStyleVar_ItemSpacing,         // ImVec2
	ImGuiStyleVar_ItemInnerSpacing,    // ImVec2
	ImGuiStyleVar_IndentSpacing,       // float
	ImGuiStyleVar_GrabMinSize          // float
}

enum
{
    ImGuiAlign_Left     = 1 << 0,
    ImGuiAlign_Center   = 1 << 1,
    ImGuiAlign_Right    = 1 << 2,
    ImGuiAlign_Top      = 1 << 3,
    ImGuiAlign_VCenter  = 1 << 4,
    ImGuiAlign_Default  = ImGuiAlign_Left | ImGuiAlign_Top,
}

enum
{
	ImGuiColorEditMode_UserSelect = -2,
	ImGuiColorEditMode_UserSelectShowButton = -1,
	ImGuiColorEditMode_RGB = 0,
	ImGuiColorEditMode_HSV = 1,
	ImGuiColorEditMode_HEX = 2
}

enum
{
	ImGuiMouseCursor_Arrow = 0,
	ImGuiMouseCursor_TextInput,         // When hovering over InputText, etc.
	ImGuiMouseCursor_Move,              // Unused
	ImGuiMouseCursor_ResizeNS,          // Unused
	ImGuiMouseCursor_ResizeEW,          // When hovering over a column
	ImGuiMouseCursor_ResizeNESW,        // Unused
	ImGuiMouseCursor_ResizeNWSE,        // When hovering over the bottom-right corner of a window
	ImGuiMouseCursor_Count_
}

align(1) struct ImVec2
{
	float x=0;
	float y=0;
	ImVec2 opBinary(string op)(const auto ref ImVec2 other) const
	{
		return mixin("ImVec2(x"~op~"other.x,y"~op~"other.y)");
	}
}

align(1) struct ImVec4
{
	float x=0;
	float y=0;
	float z=0;
	float w=0;
}

//struct ImFont{}
//struct ImFontAtlas{}
//struct ImDrawList{}
//struct ImGuiStorage{}
align(1) struct ImFontAtlas
{
	void*                       TexID;              // User data to refer to the texture once it has been uploaded to user's graphic systems. It ia passed back to you during rendering.
    ubyte*                      TexPixelsAlpha8;    // 1 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight
    uint*         		        TexPixelsRGBA32;    // 4 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight * 4
    int                         TexWidth;
    int                         TexHeight;
    ImVec2                      TexUvWhitePixel;    // Texture coordinates to a white pixel (part of the TexExtraData block)
    ImVector!(ImFont*)          Fonts;
    ImVector!(ImFontConfig)     ConfigData;         // Internal data
}

align(1) struct ImFont
{
    // Members: Settings
    float                       FontSize;           // <user set>      // Height of characters, set during loading (don't change after loading)
    float                       Scale;              // = 1.0f          // Base font scale, multiplied by the per-window font scale which you can adjust with SetFontScale()
    ImVec2                      DisplayOffset;      // = (0.0f,0.0f)   // Offset font rendering by xx pixels
    ImWchar                     FallbackChar;       // = '?'           // Replacement glyph if one isn't found. Only set via SetFallbackChar()
    ImFontConfig*               ConfigData;         //                 // Pointer within ImFontAtlas->ConfigData
    int                         ConfigDataCount;    //

    // Members: Runtime data
    align(1) static struct Glyph
    {
        ImWchar                 Codepoint;
        float                   XAdvance;
        float                   X0, Y0, X1, Y1;
        float                   U0, V0, U1, V1;     // Texture coordinates
    };
    float                       Ascent, Descent;    // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize]
    ImFontAtlas*                ContainerAtlas;     // What we has been loaded into
    ImVector!Glyph              Glyphs;
    const Glyph*                FallbackGlyph;      // == FindGlyph(FontFallbackChar)
    float                       FallbackXAdvance;   //
    ImVector!float              IndexXAdvance;      // Sparse. Glyphs->XAdvance directly indexable (for CalcTextSize functions which are often bottleneck in large UI)
    ImVector!int                IndexLookup;        // Sparse. Index glyphs by Unicode code-point
}

align(1) struct ImDrawList
{
    // This is what you have to render
    ImVector!ImDrawCmd      CmdBuffer;          // Commands. Typically 1 command = 1 gpu draw call.
    ImVector!ImDrawIdx      IdxBuffer;          // Index buffer. Each command consume ImDrawCmd::ElemCount of those
    ImVector!ImDrawVert     VtxBuffer;          // Vertex buffer.

    // [Internal, used while building lists]
    const char*             _OwnerName;         // Pointer to owner window's name (if any) for debugging
    uint          		    _VtxCurrentIdx;     // [Internal] == VtxBuffer.Size
    ImDrawVert*             _VtxWritePtr;       // [Internal] point within VtxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
    ImDrawIdx*              _IdxWritePtr;       // [Internal] point within IdxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
    ImVector!ImVec4         _ClipRectStack;     // [Internal]
    ImVector!ImTextureID    _TextureIdStack;    // [Internal]
    ImVector!ImVec2         _Path;              // [Internal] current path building
    int                     _ChannelsCurrent;   // [Internal] current channel number (0)
    int                     _ChannelsCount;     // [Internal] number of active channels (1+)
    ImVector!ImDrawChannel  _Channels;          // [Internal] draw channels for columns API (not resized down so _ChannelsCount may be smaller than _Channels.Size)
}

align(1) struct ImGuiStorage
{
    align(1) static struct Pair
    {
        ImGuiID key;
        union { int val_i; float val_f; void* val_p; };
    };
    ImVector!Pair    Data;
}

align(1) struct ImDrawChannel
{
    ImVector!ImDrawCmd CmdBuffer;
    ImVector!ImDrawIdx IdxBuffer;
}

alias uint ImU32;
alias ushort ImWchar;     // character for display
alias void* ImTextureID;          // user data to refer to a texture (e.g. store your texture handle/id)
alias ImU32 ImGuiID;              // unique ID used by widgets (typically hashed from a stack of string)
alias int ImGuiCol;               // enum ImGuiCol_
alias int ImGuiStyleVar;          // enum ImGuiStyleVar_
alias int ImGuiKey;               // enum ImGuiKey_
alias int ImGuiAlign;             // enum ImGuiAlign_
alias int ImGuiColorEditMode;     // enum ImGuiColorEditMode_
alias int ImGuiMouseCursor;       // enum ImGuiMouseCursor_
alias int ImGuiWindowFlags;       // enum ImGuiWindowFlags_
alias int ImGuiSetCond;           // enum ImGuiSetCond_
alias int ImGuiInputTextFlags;    // enum ImGuiInputTextFlags_
alias int ImGuiSelectableFlags;   // enum ImGuiSelectableFlags_
alias int function(ImGuiTextEditCallbackData *data) ImGuiTextEditCallback;

extern(C) nothrow {
    alias RenderDrawListFunc = void function(ImDrawData* data);
    alias GetClipboardTextFunc = const(char)* function();
    alias SetClipboardTextFunc = void function(const(char)*);
    alias MemAllocFunc = void* function(size_t);
    alias MemFreeFunc = void function(void*);
    alias ImeSetInputScreenPosFunc = void function(int,int);
}

// Shared state of InputText(), passed to callback when a ImGuiInputTextFlags_Callback* flag is used.
align(1) struct ImGuiTextEditCallbackData
{
    ImGuiInputTextFlags EventFlag;      // One of ImGuiInputTextFlags_Callback* // Read-only
    ImGuiInputTextFlags Flags;          // What user passed to InputText()      // Read-only
    void*               UserData;       // What user passed to InputText()      // Read-only

    // CharFilter event:
    ImWchar             EventChar;      // Character input                      // Read-write (replace character or set to zero)

    // Completion,History,Always events:
    ImGuiKey            EventKey;       // Key pressed (Up/Down/TAB)            // Read-only
    char*               Buf;            // Current text                         // Read-write (pointed data only)
    size_t              BufSize;        //                                      // Read-only
    bool                BufDirty;       // Set if you modify Buf directly       // Write
    int                 CursorPos;      //                                      // Read-write
    int                 SelectionStart; //                                      // Read-write (== to SelectionEnd when no selection)
    int                 SelectionEnd;   //                                      // Read-write

    // NB: calling those function loses selection.
    //void DeleteChars(int pos, int bytes_count);
    //void InsertChars(int pos, const char* text, const char* text_end = NULL);
};

align(1) struct ImGuiIO
{
	ImVec2        DisplaySize;              // <unset>              // Display size, in pixels. For clamping windows positions.
	float         DeltaTime;                // = 1.0f/60.0f         // Time elapsed since last frame, in seconds.
	float         IniSavingRate;            // = 5.0f               // Maximum time between saving positions/sizes to .ini file, in seconds.
	const char*   IniFilename;              // = "imgui.ini"        // Path to .ini file. NULL to disable .ini saving.
	const char*   LogFilename;              // = "imgui_log.txt"    // Path to .log file (default parameter to ImGui::LogToFile when no file is specified).
	float         MouseDoubleClickTime;     // = 0.30f              // Time for a double-click, in seconds.
	float         MouseDoubleClickMaxDist;  // = 6.0f               // Distance threshold to stay in to validate a double-click, in pixels.
	float         MouseDragThreshold;       // = 6.0f               // Distance threshold before considering we are dragging
	int[ImGuiKey_COUNT]           KeyMap;   // <unset>              // Map of indices into the KeysDown[512] entries array
    float         KeyRepeatDelay;           // = 0.250f             // When holding a key/button, time before it starts repeating, in seconds. (for actions where 'repeat' is active)
    float         KeyRepeatRate;            // = 0.020f             // When holding a key/button, rate at which it repeats, in seconds.
	void*         UserData;                 // = NULL               // Store your own data for retrieval by callbacks.

	ImFontAtlas*  Fonts;                    // <auto>               // Load and assemble one or more fonts into a single tightly packed texture. Output to Fonts array.
	float         FontGlobalScale;          // = 1.0f               // Global scale all fonts
	bool          FontAllowUserScaling;     // = false              // Allow user scaling text of individual window with CTRL+Wheel.
    ImVec2        DisplayFramebufferScale;  // = (1.0f,1.0f)        // For retina display or other situations where window coordinates are different from framebuffer coordinates. User storage only, presently not used by ImGui.
	ImVec2        DisplayVisibleMin;        // <unset> (0.0f,0.0f)  // If you use DisplaySize as a virtual space larger than your screen, set DisplayVisibleMin/Max to the visible area.
	ImVec2        DisplayVisibleMax;        // <unset> (0.0f,0.0f)  // If the values are the same, we defaults to Min=(0.0f) and Max=DisplaySize

	//------------------------------------------------------------------
	// User Functions
	//------------------------------------------------------------------

	// REQUIRED: rendering function.
	// See example code if you are unsure of how to implement this.
    RenderDrawListFunc RenderDrawListsFn;

	// Optional: access OS clipboard
	// (default to use native Win32 clipboard on Windows, otherwise uses a private clipboard. Override to access OS clipboard on other architectures)
    GetClipboardTextFunc GetClipboardTextFn;
    SetClipboardTextFunc SetClipboardTextFn;

	// Optional: override memory allocations. MemFreeFn() may be called with a NULL pointer.
	// (default to posix malloc/free)
	MemAllocFunc MemAllocFn;
    MemFreeFunc MemFreeFn;

	// Optional: notify OS Input Method Editor of the screen position of your cursor for text input position (e.g. when using Japanese/Chinese IME in Windows)
	// (default to use native imm32 api on Windows)
    ImeSetInputScreenPosFunc ImeSetInputScreenPosFn;
	void*       ImeWindowHandle;            // (Windows) Set this to your HWND to get automatic IME cursor positioning.

	//------------------------------------------------------------------
	// Input - Fill before calling NewFrame()
	//------------------------------------------------------------------

	ImVec2      	MousePos;                   // Mouse position, in pixels (set to -1,-1 if no mouse / on another screen, etc.)
	bool[5]     	MouseDown;        		    // Mouse buttons. ImGui itself only uses button 0 (left button). Others buttons allows to track if mouse is being used by your application + available to user as a convenience via IsMouse** API.
	float       	MouseWheel;                 // Mouse wheel: 1 unit scrolls about 5 lines text.
	bool        	MouseDrawCursor;            // Request ImGui to draw a mouse cursor for you (if you are on a platform without a mouse cursor).
	bool        	KeyCtrl;                    // Keyboard modifier pressed: Control
	bool        	KeyShift;                   // Keyboard modifier pressed: Shift
	bool        	KeyAlt;                     // Keyboard modifier pressed: Alt
	bool[512]   	KeysDown;              // Keyboard keys that are pressed (in whatever storage order you naturally have access to keyboard data)
	ImWchar[16+1]   InputCharacters;      // List of characters input (translated by user from keypress+keyboard state). Fill using AddInputCharacter() helper.

	//------------------------------------------------------------------
	// Output - Retrieve after calling NewFrame(), you can use them to discard inputs or hide them from the rest of your application
	//------------------------------------------------------------------

	bool        WantCaptureMouse;           // Mouse is hovering a window or widget is active (= ImGui will use your mouse input)
	bool        WantCaptureKeyboard;        // Widget is active (= ImGui will use your keyboard input)
    bool        WantTextInput;              // Some text input widget is active, which will read input characters from the InputCharacters array.
	float       Framerate;                  // Framerate estimation, in frame per second. Rolling average estimation based on IO.DeltaTime over 120 frames
    int         MetricsAllocs;              // Number of active memory allocations
    int         MetricsRenderVertices;      // Vertices processed during last call to Render()
    int         MetricsRenderIndices;       //
    int         MetricsActiveWindows;       // Number of visible windows (exclude child windows)

	//------------------------------------------------------------------
	// [Internal] ImGui will maintain those fields for you
	//------------------------------------------------------------------

	ImVec2      MousePosPrev;               // Previous mouse position
	ImVec2      MouseDelta;                 // Mouse delta. Note that this is zero if either current or previous position are negative to allow mouse enabling/disabling.
	bool[5]     MouseClicked;            // Mouse button went from !Down to Down
	ImVec2[5]   MouseClickedPos;         // Position at time of clicking
	float[5]    MouseClickedTime;        // Time of last click (used to figure out double-click)
	bool[5]     MouseDoubleClicked;      // Has mouse button been double-clicked?
    bool[5]     MouseReleased;           // Mouse button went from Down to !Down
	bool[5]     MouseDownOwned;          // Track if button was clicked inside a window. We don't request mouse capture from the application if click started outside ImGui bounds.
    float[5]    MouseDownDuration;       // Duration the mouse button has been down (0.0f == just clicked)
    float[5]    MouseDownDurationPrev;   // Previous time the mouse button has been down
	float[5]    MouseDragMaxDistanceSqr; // Squared maximum distance of how much mouse has traveled from the click point
    float[512]  KeysDownDuration;      // Duration the keyboard key has been down (0.0f == just pressed)
    float[512]  KeysDownDurationPrev;  // Previous duration the key has been down
}

align(1) struct ImGuiStyle
{
    float       Alpha;                      // Global alpha applies to everything in ImGui
    ImVec2      WindowPadding;              // Padding within a window
    ImVec2      WindowMinSize;              // Minimum window size
    float       WindowRounding;             // Radius of window corners rounding. Set to 0.0f to have rectangular windows
    ImGuiAlign  WindowTitleAlign;           // Alignment for title bar text
    float       ChildWindowRounding;        // Radius of child window corners rounding. Set to 0.0f to have rectangular windows
    ImVec2      FramePadding;               // Padding within a framed rectangle (used by most widgets)
    float       FrameRounding;              // Radius of frame corners rounding. Set to 0.0f to have rectangular frame (used by most widgets).
    ImVec2      ItemSpacing;                // Horizontal and vertical spacing between widgets/lines
    ImVec2      ItemInnerSpacing;           // Horizontal and vertical spacing between within elements of a composed widget (e.g. a slider and its label)
    ImVec2      TouchExtraPadding;          // Expand reactive bounding box for touch-based system where touch position is not accurate enough. Unfortunately we don't sort widgets so priority on overlap will always be given to the first widget. So don't grow this too much!
    float       WindowFillAlphaDefault;     // Default alpha of window background, if not specified in ImGui::Begin()
    float       IndentSpacing;              // Horizontal indentation when e.g. entering a tree node
    float       ColumnsMinSpacing;          // Minimum horizontal spacing between two columns
    float       ScrollbarSize;             // Width of the vertical scrollbar
    float       ScrollbarRounding;          // Radius of grab corners for scrollbar
    float       GrabMinSize;                // Minimum width/height of a grab box for slider/scrollbar
    float       GrabRounding;               // Radius of grabs corners rounding. Set to 0.0f to have rectangular slider grabs.
    ImVec2      DisplayWindowPadding;       // Window positions are clamped to be visible within the display area by at least this amount. Only covers regular windows.
    ImVec2      DisplaySafeAreaPadding;     // If you cannot see the edge of your screen (e.g. on a TV) increase the safe area padding. Covers popups/tooltips as well regular windows.
    bool        AntiAliasedLines;           // Enable anti-aliasing on lines/borders. Disable if you are really tight on CPU/GPU.
    bool        AntiAliasedShapes;          // Enable anti-aliasing on filled shapes (rounded rectangles, circles, etc.)
    float       CurveTessellationTol;       // Tessellation tolerance. Decrease for highly tessellated curves (higher quality, more polygons), increase to reduce quality.
    ImVec4[ImGuiCol_COUNT]      Colors;
};

align(1) struct ImDrawVert
{
	ImVec2  pos;
	ImVec2  uv;
	ImU32   col;
};

alias ImDrawCallback = void function(const ImDrawList* parent_list, const ImDrawCmd* cmd) nothrow;

align(1) struct ImDrawCmd
{
    uint            ElemCount;              // Number of indices (multiple of 3) to be rendered as triangles. Vertices are stored in the callee ImDrawList's vtx_buffer[] array, indices in idx_buffer[].
    ImVec4          ClipRect;               // Clipping rectangle (x1, y1, x2, y2)
    ImTextureID     TextureId;              // User-provided texture ID. Set by user in ImfontAtlas::SetTexID() for fonts or passed to Image*() functions. Ignore if never using images or multiple fonts atlas.
    ImDrawCallback  UserCallback;           // If != NULL, call the function instead of rendering the vertices. clip_rect and texture_id will be set normally.
    void*           UserCallbackData;       // The draw callback code can access this.
}

alias ImDrawIdx = ushort;

align(1) struct ImDrawData
{
    bool            Valid;
    ImDrawList**    CmdLists;
    int             CmdListsCount;
    int             TotalVtxCount;          // For convenience, sum of all cmd_lists vtx_buffer.Size
    int             TotalIdxCount;          // For convenience, sum of all cmd_lists idx_buffer.Size
}

align(1) struct ImFontConfig
{
    void*           FontData;
    int             FontDataSize;
    bool            FontDataOwnedByAtlas=true;
    int             FontNo=0;
    float           SizePixels=0.0f;
    int             OversampleH=3, OversampleV=1;
    bool            PixelSnapH=false;
    ImVec2          GlyphExtraSpacing;
    const ImWchar*  GlyphRanges;
    bool            MergeMode=false;
    bool            MergeGlyphCenterV=false;

    // [Internal]
    char[32]        Name;
    ImFont*         DstFont;
}

align(1) struct ImColor
{
    ImU32 value;
    alias value this;

    this(ubyte r, ubyte g, ubyte b, ubyte a = 255)
    {
        value = r | (g<<8) | (b<<16) | (a<<24);
    }

    this(float r, float g, float b, float a = 1.0f)
    {
    	static float imSaturate(float f)
		{
		    return (f < 0.0f) ? 0.0f : (f > 1.0f) ? 1.0f : f;
		}
        value  = (cast(ImU32)(imSaturate(r)*255));
        value |= (cast(ImU32)(imSaturate(g)*255) << 8);
        value |= (cast(ImU32)(imSaturate(b)*255) << 16);
        value |= (cast(ImU32)(imSaturate(a)*255) << 24);
    }

    ImVec4 asImVec4() @property
    {
	    float s = 1.0f/255.0f;
	    return ImVec4((value & 0xFF) * s, ((value >> 8) & 0xFF) * s, ((value >> 16) & 0xFF) * s, (value >> 24) * s);
    }
}

alias ImGuiPlotType = int;
enum
{
    ImGuiPlotType_Lines,
    ImGuiPlotType_Histogram
}

alias ImGuiLayoutType = int;
enum
{
    ImGuiLayoutType_Vertical,
    ImGuiLayoutType_Horizontal
}

align(1) struct ImRect
{
    ImVec2          Min;    // Upper-left
    ImVec2          Max;    // Lower-right
    float width() const @property
    {
    	return Max.x - Min.x;
    }

    float height() const @property
    {
    	return Max.y - Min.y;
    }

    bool contains(ImVec2 vec) const {
    	return vec.x >= Min.x && vec.x <= Max.x &&
			vec.y >= Min.y && vec.y <= Max.y;
    }
}

align(1) struct ImVector(T)
{
    int                         Size;
    int                         Capacity;
    T*                       Data;
}

struct ImGuiDrawContext
{
    ImVec2                  CursorPos;
    ImVec2                  CursorPosPrevLine;
    ImVec2                  CursorStartPos;
    ImVec2                  CursorMaxPos;           // Implicitly calculate the size of our contents, always extending. Saved into window->SizeContents at the end of the frame
    float                   CurrentLineHeight;
    float                   CurrentLineTextBaseOffset;
    float                   PrevLineHeight;
    float                   PrevLineTextBaseOffset;
    float                   LogLinePosY;
    int                     TreeDepth;
    ImGuiID                 LastItemID;
    ImRect                  LastItemRect;
    bool                    LastItemHoveredAndUsable;
    bool                    LastItemHoveredRect;
    bool                    MenuBarAppending;
    float                   MenuBarOffsetX;
    ImVector!(ImGuiWindow*)  ChildWindows;
    ImGuiStorage*           StateStorage;
    ImGuiLayoutType         LayoutType;

    // We store the current settings outside of the vectors to increase memory locality (reduce cache misses). The vectors are rarely modified. Also it allows us to not heap allocate for short-lived windows which are not using those settings.
    bool                    ButtonRepeat;           // == ButtonRepeatStack.back() [empty == false]
    bool                    AllowKeyboardFocus;     // == AllowKeyboardFocusStack.back() [empty == true]
    float                   ItemWidth;              // == ItemWidthStack.back(). 0.0: default, >0.0: width in pixels, <0.0: align xx pixels to the right of window
    float                   TextWrapPos;            // == TextWrapPosStack.back() [empty == -1.0f]
    ImVector!(bool)          ButtonRepeatStack;
    ImVector!(bool)          AllowKeyboardFocusStack;
    ImVector!(float)         ItemWidthStack;
    ImVector!(float)         TextWrapPosStack;
    ImVector!(ImGuiGroupData)GroupStack;
    ImGuiColorEditMode      ColorEditMode;
    int[6]                  StackSizesBackup;    // Store size of various stacks for asserting

    float                   ColumnsStartX;          // Indentation / start position from left of window (increased by TreePush/TreePop, etc.)
    float                   ColumnsOffsetX;         // Offset to the current column (if ColumnsCurrent > 0). FIXME: This and the above should be a stack to allow use cases like Tree->Column->Tree. Need revamp columns API.
    int                     ColumnsCurrent;
    int                     ColumnsCount;
    ImVec2                  ColumnsStartPos;
    float                   ColumnsCellMinY;
    float                   ColumnsCellMaxY;
    bool                    ColumnsShowBorders;
    ImGuiID                 ColumnsSetID;
    ImVector!(float)         ColumnsOffsetsT;        // Columns offset normalized 0.0 (far left) -> 1.0 (far right)
}

align(1) struct ImGuiWindow
{
    char*                   Name;
    ImGuiID                 ID;
    ImGuiWindowFlags        Flags;
    ImVec2                  PosFloat;
    ImVec2                  Pos;                                // Position rounded-up to nearest pixel
    ImVec2                  Size;                               // Current size (==SizeFull or collapsed title bar size)
    ImVec2                  SizeFull;                           // Size when non collapsed
    ImVec2                  SizeContents;                       // Size of contents (== extents reach of the drawing cursor) from previous frame
    ImVec2                  SizeContentsExplicit;               // Size of contents explicitly set by the user via SetNextWindowContentSize()
    ImVec2                  WindowPadding;                      // Window padding at the time of begin. We need to lock it, in particular manipulation of the ShowBorder would have an effect
    ImGuiID                 MoveID;                             // == window->GetID("#MOVE")
    ImVec2                  Scroll;
    ImVec2                  ScrollTarget;                       // target scroll position. stored as cursor position with scrolling canceled out, so the highest point is always 0.0f. (FLT_MAX for no change)
    ImVec2                  ScrollTargetCenterRatio;            // 0.0f = scroll so that target position is at top, 0.5f = scroll so that target position is centered
    bool                    ScrollbarX, ScrollbarY;
    ImVec2                  ScrollbarSizes;                     //
    bool                    Active;                             // Set to true on Begin()
    bool                    WasActive;
    bool                    Accessed;                           // Set to true when any widget access the current window
    bool                    Collapsed;                          // Set when collapsing window to become only title-bar
    bool                    SkipItems;                          // == Visible && !Collapsed
    int                     BeginCount;                         // Number of Begin() during the current frame (generally 0 or 1, 1+ if appending via multiple Begin/End pairs)
    ImGuiID                 PopupID;                            // ID in the popup stack when this window is used as a popup/menu (because we use generic Name/ID for recycling)
    int                     AutoFitFramesX, AutoFitFramesY;
    bool                    AutoFitOnlyGrows;
    int                     AutoPosLastDirection;
    int                     HiddenFrames;
    int                     SetWindowPosAllowFlags;             // bit ImGuiSetCond_*** specify if SetWindowPos() call will succeed with this particular flag.
    int                     SetWindowSizeAllowFlags;            // bit ImGuiSetCond_*** specify if SetWindowSize() call will succeed with this particular flag.
    int                     SetWindowCollapsedAllowFlags;       // bit ImGuiSetCond_*** specify if SetWindowCollapsed() call will succeed with this particular flag.
    bool                    SetWindowPosCenterWanted;

    ImGuiDrawContext        DC;                                 // Temporary per-window data, reset at the beginning of the frame
    ImVector!(ImGuiID)   	IDStack;                            // ID stack. ID are hashes seeded with the value at the top of the stack
    ImRect                  ClipRect;                           // = DrawList->clip_rect_stack.back(). Scissoring / clipping rectangle. x1, y1, x2, y2.
    ImRect                  ClippedWindowRect;                  // = ClipRect just after setup in Begin()
    int                     LastFrameDrawn;
    float                   ItemWidthDefault;
    ImGuiSimpleColumns      MenuColumns;                        // Simplified columns storage for menu items
    ImGuiStorage            StateStorage;
    float                   FontWindowScale;                    // Scale multiplier per-window
    ImDrawList*             DrawList;
    ImGuiWindow*            RootWindow;
    ImGuiWindow*            RootNonPopupWindow;

    // Focus
    int                     FocusIdxAllCounter;                 // Start at -1 and increase as assigned via FocusItemRegister()
    int                     FocusIdxTabCounter;                 // (same, but only count widgets which you can Tab through)
    int                     FocusIdxAllRequestCurrent;          // Item being requested for focus
    int                     FocusIdxTabRequestCurrent;          // Tab-able item being requested for focus
    int                     FocusIdxAllRequestNext;             // Item being requested for focus, for next update (relies on layout to be stable between the frame pressing TAB and the next frame)
    int                     FocusIdxTabRequestNext;             // "
}

align(1) struct ImGuiGroupData
{
    ImVec2          BackupCursorPos;
    ImVec2          BackupCursorMaxPos;
    float           BackupColumnsStartX;
    float           BackupCurrentLineHeight;
    float           BackupCurrentLineTextBaseOffset;
    float           BackupLogLinePosY;
    bool            AdvanceCursor;
}

align(1) struct ImGuiSimpleColumns
{
    int             Count;
    float           Spacing;
    float           Width, NextWidth;
    float[8]        Pos, NextWidths;
}

alias ImGuiButtonFlags = int;
enum
{
    ImGuiButtonFlags_Repeat             = 1 << 0,
    ImGuiButtonFlags_PressedOnClick     = 1 << 1,   // return pressed on click only (default requires click+release)
    ImGuiButtonFlags_PressedOnRelease   = 1 << 2,   // return pressed on release only (default requires click+release)
    ImGuiButtonFlags_FlattenChilds      = 1 << 3,
    ImGuiButtonFlags_DontClosePopups    = 1 << 4,
    ImGuiButtonFlags_Disabled           = 1 << 5,
    ImGuiButtonFlags_AlignTextBaseLine  = 1 << 6
};

alias ImGuiTreeNodeFlags = int;
enum
{
    ImGuiTreeNodeFlags_DefaultOpen          = 1 << 0,
    ImGuiTreeNodeFlags_NoAutoExpandOnLog    = 1 << 1
};

// Main state for ImGui
align(1) struct ImGuiState
{
    bool                    Initialized;
    ImGuiIO                 IO;
    ImGuiStyle              Style;
    ImFont*                 Font;                               // (Shortcut) == FontStack.empty() ? IO.Font : FontStack.back()
    float                   FontSize;                           // (Shortcut) == FontBaseSize * g.CurrentWindow->FontWindowScale == window->FontSize()
    float                   FontBaseSize;                       // (Shortcut) == IO.FontGlobalScale * Font->Scale * Font->FontSize. Size of characters.
    ImVec2                  FontTexUvWhitePixel;                // (Shortcut) == Font->TexUvForWhite

    float                   Time;
    int                     FrameCount;
    int                     FrameCountRendered;
    ImVector!(ImGuiWindow*) Windows;
    ImVector!(ImGuiWindow*) WindowsSortBuffer;
    ImGuiWindow*            CurrentWindow;                      // Being drawn into
    ImVector!(ImGuiWindow*) CurrentWindowStack;
    ImGuiWindow*            FocusedWindow;                      // Will catch keyboard inputs
    ImGuiWindow*            HoveredWindow;                      // Will catch mouse inputs
    ImGuiWindow*            HoveredRootWindow;                  // Will catch mouse inputs (for focus/move only)
    ImGuiID                 HoveredId;                          // Hovered widget
    ImGuiID                 HoveredIdPreviousFrame;
    ImGuiID                 ActiveId;                           // Active widget
    ImGuiID                 ActiveIdPreviousFrame;
    bool                    ActiveIdIsAlive;
    bool                    ActiveIdIsJustActivated;            // Set at the time of activation for one frame
    bool                    ActiveIdIsFocusedOnly;              // Set only by active widget. Denote focus but no active interaction
    ImGuiWindow*            ActiveIdWindow;
    ImGuiWindow*            MovedWindow;                        // Track the child window we clicked on to move a window. Pointer is only valid if ActiveID is the "#MOVE" identifier of a window.
    ImVector!(ImGuiIniData) Settings;                           // .ini Settings
    float                   SettingsDirtyTimer;                 // Save .ini settinngs on disk when time reaches zero
    int                     DisableHideTextAfterDoubleHash;
    ImVector!(ImGuiColMod)   ColorModifiers;                     // Stack for PushStyleColor()/PopStyleColor()
    ImVector!(ImGuiStyleMod) StyleModifiers;                     // Stack for PushStyleVar()/PopStyleVar()
    ImVector!(ImFont*)       FontStack;                          // Stack for PushFont()/PopFont()
    ImVector!(ImGuiPopupRef) OpenedPopupStack;                   // Which popups are open (persistent)
    ImVector!(ImGuiPopupRef) CurrentPopupStack;                  // Which level of BeginPopup() we are in (reset every frame)

    // Storage for SetNexWindow** and SetNextTreeNode*** functions
    ImVec2                  SetNextWindowPosVal;
    ImVec2                  SetNextWindowSizeVal;
    ImVec2                  SetNextWindowContentSizeVal;
    bool                    SetNextWindowCollapsedVal;
    ImGuiSetCond            SetNextWindowPosCond;
    ImGuiSetCond            SetNextWindowSizeCond;
    ImGuiSetCond            SetNextWindowContentSizeCond;
    ImGuiSetCond            SetNextWindowCollapsedCond;
    bool                    SetNextWindowFocus;
    bool                    SetNextTreeNodeOpenedVal;
    ImGuiSetCond            SetNextTreeNodeOpenedCond;

    // Render
    ImVector!(ImDrawList*)[3] RenderDrawLists;
    float                   ModalWindowDarkeningRatio;
    ImDrawList              OverlayDrawList;                    // Optional software render of mouse cursors, if io.MouseDrawCursor is set + a few debug overlays
    ImGuiMouseCursor        MouseCursor;
    ImGuiMouseCursorData[ImGuiMouseCursor_Count_]    MouseCursorData;

    // Widget state
    ImGuiTextEditState      InputTextState;
    ImGuiID                 ScalarAsInputTextId;                // Temporary text input when CTRL+clicking on a slider, etc.
    ImGuiStorage            ColorEditModeStorage;               // Store user selection of color edit mode
    ImVec2                  ActiveClickDeltaToCenter;
    float                   DragCurrentValue;                   // Currently dragged value, always float, not rounded by end-user precision settings
    ImVec2                  DragLastMouseDelta;
    float                   DragSpeedDefaultRatio;              // If speed == 0.0f, uses (max-min) * DragSpeedDefaultRatio
    float                   DragSpeedScaleSlow;
    float                   DragSpeedScaleFast;
    ImVec2                  ScrollbarClickDeltaToGrabCenter;   // Distance between mouse and center of grab box, normalized in parent space. Use storage?
    char[1024]              Tooltip;
    char*                   PrivateClipboard;                   // If no custom clipboard handler is defined

    import std.stdio : FILE;
    // Logging
    bool                    LogEnabled;
    FILE*                   LogFile;                            // If != NULL log to stdout/ file
    ImGuiTextBuffer*        LogClipboard;                       // Else log to clipboard. This is pointer so our GImGui static constructor doesn't call heap allocators.
    int                     LogStartDepth;
    int                     LogAutoExpandMaxDepth;

    // Misc
    float[120]              FramerateSecPerFrame;          // calculate estimate of framerate for user
    int                     FramerateSecPerFrameIdx;
    float                   FramerateSecPerFrameAccum;
    bool                    CaptureMouseNextFrame;              // explicit capture via CaptureInputs() sets those flags
    bool                    CaptureKeyboardNextFrame;
    char[1024*3+1]          TempBuffer;               // temporary text buffer
}

align(1) struct ImGuiIniData
{
    char*               Name;
    ImGuiID             ID;
    ImVec2              Pos;
    ImVec2              Size;
    bool                Collapsed;
}

align(1) struct ImGuiColMod
{
    ImGuiCol        Col;
    ImVec4          PreviousValue;
}

align(1) struct ImGuiStyleMod
{
    ImGuiStyleVar   Var;
    ImVec2          PreviousValue;
}

align(1) struct ImGuiPopupRef
{
    ImGuiID             PopupID;        // Set on OpenPopup()
    ImGuiWindow*        Window;         // Resolved on BeginPopup() - may stay unresolved if user never calls OpenPopup()
    ImGuiWindow*        ParentWindow;   // Set on OpenPopup()
    ImGuiID             ParentMenuSet;  // Set on OpenPopup()
    ImVec2              MousePosOnOpen; // Copy of mouse position at the time of opening popup
}

// Mouse cursor data (used when io.MouseDrawCursor is set)
align(1) struct ImGuiMouseCursorData
{
    ImGuiMouseCursor    Type;
    ImVec2              HotOffset;
    ImVec2              Size;
    ImVec2[2]           TexUvMin;
    ImVec2[2]           TexUvMax;
}

// Helper: Text buffer for logging/accumulating text
align(1) struct ImGuiTextBuffer
{
    ImVector!char Buf;
}

align(1) struct ImGuiTextEditState
{
    ImGuiID             Id;                             // widget id owning the text state
    ImVector!ImWchar   Text;                           // edit buffer, we need to persist but can't guarantee the persistence of the user-provided buffer. so we copy into own buffer.
    ImVector!char      InitialText;                    // backup of end-user buffer at the time of focus (in UTF-8, unaltered)
    ImVector!char      TempTextBuffer;
    int                 CurLenA, CurLenW;               // we need to maintain our buffer length in both UTF-8 and wchar format.
    int                 BufSizeA;                       // end-user buffer size
    float               ScrollX;
    STB_TexteditState   StbState;
    float               CursorAnim;
    bool                CursorFollow;
    ImVec2              InputCursorScreenPos;           // Cursor position in screen space to be used by IME callback.
    bool                SelectedAllMouseLock;
}

align(1) struct STB_TexteditState
{
   int cursor;
   int select_start;
   int select_end;
   ubyte insert_mode;
   ubyte cursor_at_end_of_line; // not implemented yet
   ubyte initialized;
   ubyte has_preferred_x;
   ubyte single_line;
   ubyte padding1, padding2, padding3;
   float preferred_x;
   StbUndoState undostate;
}

enum STB_TEXTEDIT_UNDOSTATECOUNT = 99;
enum STB_TEXTEDIT_UNDOCHARCOUNT = 999;
alias STB_TEXTEDIT_CHARTYPE = int;
alias STB_TEXTEDIT_POSITIONTYPE = int;

align(1) struct StbUndoState
{
   // private data
   StbUndoRecord[STB_TEXTEDIT_UNDOSTATECOUNT]  undo_rec;
   STB_TEXTEDIT_CHARTYPE[STB_TEXTEDIT_UNDOCHARCOUNT] undo_char;
   short undo_point, redo_point;
   short undo_char_point, redo_char_point;
}

align(1) struct StbUndoRecord
{
   // private data
   STB_TEXTEDIT_POSITIONTYPE  where;
   short           insert_length;
   short           delete_length;
   short           char_storage;
}
