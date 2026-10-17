import os
import shutil
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

def set_cell_shading(cell, color_hex):
    """Sets background color of a table cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    # Remove existing shading if present
    for child in list(tc_pr):
        if child.tag.endswith('shd'):
            tc_pr.remove(child)
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>')
    tc_pr.append(shd)

def set_cell_margins(cell, top=140, bottom=140, left=200, right=200):
    """Sets internal padding (in twips) for a cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = parse_xml(
        f'<w:tcMar {nsdecls("w")}>'
        f'<w:top w:w="{top}" w:type="dxa"/>'
        f'<w:bottom w:w="{bottom}" w:type="dxa"/>'
        f'<w:left w:w="{left}" w:type="dxa"/>'
        f'<w:right w:w="{right}" w:type="dxa"/>'
        f'</w:tcMar>'
    )
    tc_pr.append(tc_mar)

def set_cell_borders(cell, top=None, bottom=None, left=None, right=None):
    """Sets custom borders on a cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    borders = parse_xml(f'<w:tcBorders {nsdecls("w")}/>')
    for side, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        if val:
            b_xml = parse_xml(
                f'<w:{side} {nsdecls("w")} w:val="{val.get("val", "single")}" '
                f'w:sz="{val.get("sz", "4")}" w:space="0" w:color="{val.get("color", "auto")}"/>'
            )
            borders.append(b_xml)
        else:
            b_xml = parse_xml(f'<w:{side} {nsdecls("w")} w:val="none"/>')
            borders.append(b_xml)
    tc_pr.append(borders)

def add_callout(doc, quote_text, attribution=None):
    """Adds an executive callout block with a left amber accent bar."""
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.5)
    set_cell_shading(cell, "FFF9F2") # Warm subtle amber tint
    set_cell_margins(cell, top=180, bottom=180, left=240, right=200)
    set_cell_borders(cell, left={"val": "single", "sz": "28", "color": "E65100"}) # 3.5pt solid orange border
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.15
    run = p.add_run(f'“{quote_text}”')
    run.font.name = "Calibri"
    run.font.size = Pt(11)
    run.font.italic = True
    run.font.color.rgb = RGBColor(40, 44, 52)
    
    if attribution:
        p2 = cell.add_paragraph()
        p2.paragraph_format.space_before = Pt(4)
        p2.paragraph_format.space_after = Pt(2)
        p2.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        run_attr = p2.add_run(f'— {attribution}')
        run_attr.font.name = "Calibri"
        run_attr.font.size = Pt(9.5)
        run_attr.font.bold = True
        run_attr.font.color.rgb = RGBColor(230, 81, 0)
    
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def add_code_block(doc, code_snippet, language="Ember Script"):
    """Adds a dark-themed, cleanly styled syntax code block."""
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.5)
    set_cell_shading(cell, "1E222A") # Dark slate
    set_cell_margins(cell, top=140, bottom=140, left=180, right=180)
    set_cell_borders(cell, left={"val": "single", "sz": "18", "color": "F57C00"})
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.05
    
    # Tag
    run_tag = p.add_run(f"// Language: {language}\n")
    run_tag.font.name = "Consolas"
    run_tag.font.size = Pt(8.5)
    run_tag.font.color.rgb = RGBColor(140, 150, 165)
    
    run_code = p.add_run(code_snippet)
    run_code.font.name = "Consolas"
    run_code.font.size = Pt(9.5)
    run_code.font.color.rgb = RGBColor(220, 225, 235)
    
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def style_heading_1(p, text):
    p.paragraph_format.space_before = Pt(16)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    run = p.add_run(text)
    run.font.name = "Segoe UI"
    run.font.size = Pt(16)
    run.font.bold = True
    run.font.color.rgb = RGBColor(26, 32, 44)
    return run

def style_heading_2(p, text):
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    run = p.add_run(text)
    run.font.name = "Segoe UI"
    run.font.size = Pt(13)
    run.font.bold = True
    run.font.color.rgb = RGBColor(230, 81, 0)
    return run

def style_heading_3(p, text):
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.keep_with_next = True
    run = p.add_run(text)
    run.font.name = "Segoe UI"
    run.font.size = Pt(11)
    run.font.bold = True
    run.font.color.rgb = RGBColor(45, 55, 72)
    return run

def add_body_p(doc, text="", bold_prefix=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.18
    if bold_prefix:
        r_b = p.add_run(bold_prefix)
        r_b.font.name = "Calibri"
        r_b.font.size = Pt(11)
        r_b.font.bold = True
        r_b.font.color.rgb = RGBColor(30, 35, 45)
    if text:
        r = p.add_run(text)
        r.font.name = "Calibri"
        r.font.size = Pt(11)
        r.font.color.rgb = RGBColor(55, 65, 81)
    return p

def add_bullet_p(doc, text, bold_prefix=None):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_before = Pt(1)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        r_b = p.add_run(bold_prefix)
        r_b.font.name = "Calibri"
        r_b.font.size = Pt(11)
        r_b.font.bold = True
        r_b.font.color.rgb = RGBColor(30, 35, 45)
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(11)
    r.font.color.rgb = RGBColor(55, 65, 81)
    return p

def add_caption(doc, caption_text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(10)
    run = p.add_run(caption_text)
    run.font.name = "Calibri"
    run.font.size = Pt(9.5)
    run.font.italic = True
    run.font.color.rgb = RGBColor(115, 125, 140)

def main():
    doc = docx.Document()
    
    # Configure 1-inch margins
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)
    
    # -------------------------------------------------------------
    # HEADER / BRANDING BANNER
    # -------------------------------------------------------------
    icon_path = r"c:\Dev\ember engine\assets\branding\ember_icon_512.png"
    
    # Header block table (Logo on left, Title & Tagline on right)
    header_table = doc.add_table(rows=1, cols=2)
    header_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    header_table.autofit = False
    
    c_logo = header_table.cell(0, 0)
    c_logo.width = Inches(1.2)
    c_logo.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    set_cell_borders(c_logo)
    
    if os.path.exists(icon_path):
        p_logo = c_logo.paragraphs[0]
        p_logo.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p_logo.paragraph_format.space_after = Pt(0)
        p_logo.add_run().add_picture(icon_path, width=Inches(1.05))
    
    c_text = header_table.cell(0, 1)
    c_text.width = Inches(5.3)
    c_text.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    set_cell_borders(c_text)
    
    p_meta = c_text.paragraphs[0]
    p_meta.paragraph_format.space_after = Pt(2)
    r_cat = p_meta.add_run("FLUTTER & GAME DEVELOPMENT  |  ENGINEERING SPOTLIGHT")
    r_cat.font.name = "Segoe UI"
    r_cat.font.size = Pt(9)
    r_cat.font.bold = True
    r_cat.font.color.rgb = RGBColor(230, 81, 0) # Ember Orange
    
    p_title = c_text.add_paragraph()
    p_title.paragraph_format.space_before = Pt(2)
    p_title.paragraph_format.space_after = Pt(2)
    r_t = p_title.add_run("Building Games in Flutter Just Leveled Up")
    r_t.font.name = "Segoe UI"
    r_t.font.size = Pt(22)
    r_t.font.bold = True
    r_t.font.color.rgb = RGBColor(24, 28, 36)
    
    p_sub = c_text.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(4)
    r_s = p_sub.add_run("Introducing Ember Engine: The 2D + 3D Visual Editor & Engine Bridging the Gap for Flutter Game Developers")
    r_s.font.name = "Calibri"
    r_s.font.size = Pt(12)
    r_s.font.color.rgb = RGBColor(85, 95, 110)
    
    # Divider line
    p_div = doc.add_paragraph()
    p_div.paragraph_format.space_before = Pt(6)
    p_div.paragraph_format.space_after = Pt(12)
    r_line = p_div.add_run("―" * 58)
    r_line.font.color.rgb = RGBColor(220, 225, 230)
    
    # Author & Publication Metadata
    p_by = doc.add_paragraph()
    p_by.paragraph_format.space_after = Pt(12)
    r_by = p_by.add_run("By the Ember Engine Core Team  •  Published for LinkedIn Engineering & GameDev Communities\n")
    r_by.font.size = Pt(9.5)
    r_by.font.italic = True
    r_by.font.color.rgb = RGBColor(100, 110, 125)
    
    # -------------------------------------------------------------
    # SECTION 1: THE DILEMMA
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "1. The Dilemma: Why Making Games in Flutter Felt Incomplete")
    
    add_body_p(doc, 
        "Over the last half-decade, Flutter has fundamentally transformed multiplatform UI engineering. "
        "With a single Dart codebase, developers deliver pixel-perfect, 120 FPS applications across iOS, Android, "
        "Windows, macOS, Linux, and the web. The developer experience is legendary: instant stateful hot reload, "
        "a rich widget ecosystem, intuitive package management, and near-native performance backed by Impeller and Skia."
    )
    
    add_body_p(doc, 
        "Naturally, thousands of passionate Flutter engineers asked the obvious question: ",
        bold_prefix="“Why can’t we build great games in Flutter?”"
    )
    
    add_body_p(doc, 
        "Up until now, taking that leap forced game developers into an uncomfortable compromise:"
    )
    
    add_bullet_p(doc, 
        "Flame is an outstanding, battle-tested 2D framework, but it is strictly code-first. Designing levels means manually hardcoding Vector2 coordinates, guessing camera bounds in code, reloading, checking debug collision shapes, and repeating. For level design, physics tuning, and narrative pacing, code-only tooling becomes an exhausting bottleneck.",
        bold_prefix="The Code-Only Limit (Flame): "
    )
    
    add_bullet_p(doc, 
        "Moving to Unity, Godot, or Unreal offers world-class visual scene editors, inspectors, and drag-and-drop gizmos. But the trade-off is painful: you abandon Dart, lose Flutter’s reactive UI ecosystem, learn C# or GDScript, fight complex FFI bridging layers, and battle bloated binary sizes on mobile.",
        bold_prefix="The External Engine Exodus (Unity / Godot): "
    )
    
    add_callout(doc, 
        "Game development is inherently visual, spatial, and iterative. Flutter engineers shouldn't have to leave the language and ecosystem they love just to get a visual scene editor, real-time inspector, and instant playtesting.",
        attribution="The Core Motivation Behind Ember Engine"
    )
    
    add_body_p(doc, 
        "What the Flutter ecosystem desperately needed was a true third path: a native game engine and visual desktop editor built entirely in Flutter, for Flutter developers. "
        "That missing piece has arrived: Ember Engine."
    )

    # -------------------------------------------------------------
    # HERO IMAGE: EDITOR SHOWCASE
    # -------------------------------------------------------------
    editor_img = r"C:\Users\tobii\.gemini\antigravity-ide\brain\392f0e0e-727b-46a1-8f1c-3178d6e3cd46\ember_editor_showcase_1791363963041.jpg"
    if os.path.exists(editor_img):
        p_img = doc.add_paragraph()
        p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img.paragraph_format.space_before = Pt(8)
        p_img.paragraph_format.space_after = Pt(2)
        p_img.add_run().add_picture(editor_img, width=Inches(6.4))
        add_caption(doc, "Figure 1: The Ember Engine Editor workspace featuring Scene Hierarchy, 3D/2D Viewport with interactive gizmos, Live Inspector, and integrated bottom drawer with Tilemap Palette.")

    # -------------------------------------------------------------
    # SECTION 2: MEET EMBER ENGINE
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "2. Meet Ember Engine: Visual Power Meets Dart Simplicity")
    
    add_body_p(doc, 
        "Ember Engine is a 2D + 3D game engine and professional desktop editor built from the ground up in Flutter and Dart. "
        "It provides the spatial, visual authoring experience of modern engines like Unity and Godot, while remaining deeply rooted in the lightweight agility of the Dart runtime."
    )
    
    style_heading_2(doc.add_paragraph(), "Key Architectural Pillars at a Glance:")
    
    add_bullet_p(doc, 
        "Inspect entity hierarchies, scrub property numbers in real-time, toggle components, transform objects with 3D translation/rotation/scale gizmos, and trigger any editor action with the global Command Palette (Ctrl+K).",
        bold_prefix="Unity-Style Desktop Editor: "
    )
    add_bullet_p(doc, 
        "Full Box2D rigid body physics powered by Forge2D (pure Dart, zero native compilation headaches). Includes mass, bounciness, friction, damping, joints (hinge, spring, weld), sensors, raycasting, and impulse explosions.",
        bold_prefix="Integrated 2D Pipeline & Tilemaps: "
    )
    add_bullet_p(doc, 
        "A lightweight software perspective renderer executing directly on Flutter Canvas. Includes perspective projection, lighting, sky gradients, depth fog, glowing emissive materials, 3D first-person controllers with mouse capture, 3D raycasting, and autonomous enemy AI.",
        bold_prefix="Native 3D Viewport & Physics: "
    )
    add_bullet_p(doc, 
        "Write entity logic in a clean, interpreted Dart-like language that compiles and binds to entities in memory. Edit running game code and see mechanics change instantaneously without triggering a Flutter rebuild.",
        bold_prefix="Ember Script (Zero-Recompile Game Logic): "
    )
    add_bullet_p(doc, 
        "Turn projects into standalone, click-and-play executables for Windows (.exe, Inno Setup installer, MSIX), Web (itch.io HTML5 ZIP), and Android (signed APK and Play Store-ready AAB).",
        bold_prefix="One-Click Multiplatform Publishing: "
    )

    # -------------------------------------------------------------
    # SECTION 3: THE SUPERPOWER OF EMBER SCRIPT
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "3. The Secret Weapon: Ember Script & Instant Live Iteration")
    
    add_body_p(doc, 
        "In traditional game programming, fine-tuning gameplay feel (such as jumping arc, weapon fire rates, or enemy chase speeds) requires frequent recompilation. "
        "Even with Flutter's fast UI hot reload, restarting game scenes or maintaining complex physics states can cause friction. "
        "To solve this, Ember Engine incorporates its own custom-engineered scripting architecture: lexer, parser, Abstract Syntax Tree (AST), and interpreter."
    )
    
    add_body_p(doc, 
        "Ember Script delivers Dart-syntax scripting that runs dynamically inside the engine runtime:",
        bold_prefix="Why this changes everything for developers: "
    )
    
    add_bullet_p(doc, 
        "Top-level script variables (like 'var speed = 180;') automatically expose scrubbable, live fields in the editor’s Inspector panel without extra configuration code.",
        bold_prefix="Instant Inspector Binding: "
    )
    add_bullet_p(doc, 
        "If you tweak an enemy's attack cooldown or adjust player momentum while the game is running, the logic updates live without resetting scores, player positions, or world state.",
        bold_prefix="Live State Retention: "
    )
    add_bullet_p(doc, 
        "A script with an error or infinite loop never crashes the editor or triggers a red error screen. The engine sandboxes execution, catches the issue, and flags it directly in the Problems tab with exact line references.",
        bold_prefix="Zero-Crash Sandboxing: "
    )

    # Code snippet block
    code_sample = """var speed = 160;
var jumpForce = 420;

void onStart() {
    self.tag = "Player";
}

void onUpdate(dt) {
    // Smooth 8-way movement & jump controls
    self.position = self.position + Input.move * speed * dt;
    
    if (Input.pressed("Space") && self.grounded) {
        self.applyImpulse(vec(0, -jumpForce));
        playSound("jump");
    }
}

void onTriggerEnter(other) {
    if (other.hasTag("Coin")) {
        destroy(other);
        playSound("coin");
        Game.data["score"] = (Game.data["score"] ?? 0) + 10;
        find("HUD_Score").text.text = "Score: ${Game.data['score']}";
    }
}"""
    add_code_block(doc, code_sample, language="Ember Script (.ember)")

    # IMAGE 2: SCRIPTING WORKFLOW
    script_img = r"C:\Users\tobii\.gemini\antigravity-ide\brain\392f0e0e-727b-46a1-8f1c-3178d6e3cd46\ember_live_scripting_1791363986260.jpg"
    if os.path.exists(script_img):
        p_img2 = doc.add_paragraph()
        p_img2.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img2.paragraph_format.space_before = Pt(8)
        p_img2.paragraph_format.space_after = Pt(2)
        p_img2.add_run().add_picture(script_img, width=Inches(6.4))
        add_caption(doc, "Figure 2: The split-screen Ember Script workflow: live coding on the left dynamically controls active game loops and entity components in real time without recompilation.")

    # -------------------------------------------------------------
    # SECTION 4: COMPARISON MATRIX
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "4. How Ember Engine Compares: Flame vs. Unity/Godot vs. Ember")
    
    add_body_p(doc, 
        "To appreciate the unique positioning of Ember Engine, consider where it fits in the current game development landscape for Flutter engineers:"
    )
    
    # Table of comparison
    comp_table = doc.add_table(rows=6, cols=4)
    comp_table.alignment = WD_TABLE_ALIGNMENT.CENTER
    comp_table.autofit = False
    
    headers = ["Feature / Dimension", "Flame Framework", "Unity / Godot", "Ember Engine"]
    col_widths = [Inches(1.8), Inches(1.5), Inches(1.5), Inches(1.7)]
    
    # Style Header Row
    hdr_cells = comp_table.rows[0].cells
    for i, title in enumerate(headers):
        hdr_cells[i].width = col_widths[i]
        set_cell_shading(hdr_cells[i], "1E232D")
        set_cell_margins(hdr_cells[i], top=120, bottom=120, left=140, right=140)
        p = hdr_cells[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run(title)
        run.font.name = "Segoe UI"
        run.font.size = Pt(9.5)
        run.font.bold = True
        run.font.color.rgb = RGBColor(255, 255, 255)
        
    table_data = [
        ("Language & Runtime", "Pure Dart", "C# / C++ / GDScript", "Pure Dart + Ember Script"),
        ("Visual Scene Editor", "None (Code-First)", "Full Desktop Editor", "Full Flutter Desktop Editor"),
        ("Live In-Game Scripting", "Flutter Hot Reload only", "Reload requires assembly recompile", "Instant AST Interpreter + Live Inspector"),
        ("2D & 3D Integration", "Primarily 2D", "Heavy 2D/3D suite", "Flame 2D + Built-in 3D Pipeline"),
        ("Export & Deployment", "Flutter CLI commands", "Proprietary build systems", "Integrated Export GUI (.exe, MSIX, Web, AAB)")
    ]
    
    for row_idx, (feat, flame_val, heavy_val, ember_val) in enumerate(table_data, start=1):
        row_cells = comp_table.rows[row_idx].cells
        bg_color = "F8F9FA" if row_idx % 2 == 1 else "FFFFFF"
        for col_idx, text in enumerate([feat, flame_val, heavy_val, ember_val]):
            row_cells[col_idx].width = col_widths[col_idx]
            set_cell_shading(row_cells[col_idx], bg_color)
            set_cell_margins(row_cells[col_idx], top=90, bottom=90, left=120, right=120)
            p = row_cells[col_idx].paragraphs[0]
            p.paragraph_format.line_spacing = 1.05
            p.paragraph_format.space_after = Pt(2)
            run = p.add_run(text)
            run.font.name = "Calibri"
            run.font.size = Pt(9.5)
            if col_idx == 0:
                run.font.bold = True
                run.font.color.rgb = RGBColor(30, 35, 45)
            elif col_idx == 3:
                run.font.bold = True
                run.font.color.rgb = RGBColor(230, 81, 0) # Highlight Ember
            else:
                run.font.color.rgb = RGBColor(70, 80, 95)
                
    doc.add_paragraph().paragraph_format.space_after = Pt(6)

    # -------------------------------------------------------------
    # SECTION 5: PRODUCTION TEMPLATES
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "5. Proven with Real Games: Five Complete Starter Templates")
    
    add_body_p(doc, 
        "Many aspiring game engines fail because they launch as empty canvases with theoretical APIs. "
        "Ember Engine takes the opposite philosophy: it ships with complete, playable genre templates that demonstrate "
        "real-world architecture from start to finish."
    )
    
    add_bullet_p(doc, 
        "A full 3D first-person wave shooter. Features portal spawners, exploding chaser drones, strafing gunners, charging brutes, projectile raycasts, weapon swapping (blaster & scattergun), health/ammo drops, dynamic fog, and high score tracking.",
        bold_prefix="Ember Arena (3D FPS Shooter): "
    )
    add_bullet_p(doc, 
        "A physics-driven destruction game in the style of Angry Birds. Utilizes Box2D rigid bodies, realistic slingshot drag physics, material-based fracturing (wood, ice, stone), explosive powder kegs, multiple levels, and 3-star scoring.",
        bold_prefix="Ember Siege (2D Physics Demolition): "
    )
    add_bullet_p(doc, 
        "A classic top-down action RPG. Features multi-layered tilemaps, A* pathfinding monster AI (slimes, bats, skeleton archers), boss encounters with the Ember Golem, typewriter NPC dialogue, sword combat, inventory, and save crystals.",
        bold_prefix="Ember Legends (Top-Down Action RPG): "
    )
    add_bullet_p(doc, 
        "A polished retro side-scroller. Implements platformer physics with coyote time, jump buffering, variable jump height, stompable enemies, breakable bricks, collectible power berries, and flagpoles.",
        bold_prefix="Ember Quest (2D Platformer Adventure): "
    )
    add_bullet_p(doc, 
        "An arcade physics game demonstrating procedural pipe obstacle generation, collision events, audio triggers, and local high-score persistence.",
        bold_prefix="Flappy Arcade (One-Button Arcade): "
    )

    # -------------------------------------------------------------
    # SECTION 6: PUBLISHING PIPELINE
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "6. The Final Mile: One-Click Multiplatform Publishing")
    
    add_body_p(doc, 
        "For indie creators, the hardest part of game development isn't writing game loops—it’s getting the build into players' hands. "
        "Configuring installers, code-signing certificates, store packages, and cross-compilation usually requires days of frustrating DevOps work."
    )
    
    add_body_p(doc, 
        "Ember Engine integrates commercial export pipelines directly into the editor UI:",
        bold_prefix="Built-in Store Readiness: "
    )
    
    add_bullet_p(doc, 
        "Builds a release .exe with the Visual C++ runtime automatically bundled (runs cleanly on PCs without VC++ installed). Generates setup installers with Inno Setup, or builds unsigned/signed MSIX packages ready for the Microsoft Partner Center.",
        bold_prefix="Windows Desktop: "
    )
    add_bullet_p(doc, 
        "Outputs pre-packaged ZIP archives with index.html at root, ready to drag-and-drop straight onto itch.io for browser play with HTML5 Canvas and WebAudio support.",
        bold_prefix="Web (itch.io): "
    )
    add_bullet_p(doc, 
        "Produces release APKs and Google Play-compliant Android App Bundles (.aab). Includes an integrated keystore creator, secure password storage via Windows Credential Manager, and automatic build incrementing.",
        bold_prefix="Android (Google Play): "
    )
    
    # IMAGE 3: CROSS PLATFORM
    cross_img = r"C:\Users\tobii\.gemini\antigravity-ide\brain\392f0e0e-727b-46a1-8f1c-3178d6e3cd46\ember_crossplatform_1791364008749.jpg"
    if os.path.exists(cross_img):
        p_img3 = doc.add_paragraph()
        p_img3.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img3.paragraph_format.space_before = Pt(8)
        p_img3.paragraph_format.space_after = Pt(2)
        p_img3.add_run().add_picture(cross_img, width=Inches(6.4))
        add_caption(doc, "Figure 3: Multiplatform export in action: target Windows Desktop, Android mobile, and itch.io Web with one-click packaging directly from Ember Engine.")

    # -------------------------------------------------------------
    # SECTION 7: STABILITY & TRUST
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "7. Engineered for Trust: Ember Doctor & Disaster Recovery")
    
    add_body_p(doc, 
        "Nothing kills creative momentum faster than an editor crash that destroys two hours of level design. "
        "The Ember Engine team treated stability and data safety as top architectural priorities:"
    )
    
    add_bullet_p(doc, 
        "Every 60 seconds (and automatically whenever you click Play), Ember Engine silently writes a snapshot recovery copy to your project’s `.recovery/` directory. If power fails or the process is interrupted, the next launch prompts you with one click: 'Restore unsaved changes?'.",
        bold_prefix="Automatic Crash Recovery: "
    )
    add_bullet_p(doc, 
        "A dedicated diagnostic subsystem (the shield icon) performs comprehensive health audits on your game. It parses scripts for syntax problems, checks that all scene triggers point to valid levels, verifies that sprite/audio assets exist on disk, and confirms export toolchains are present.",
        bold_prefix="Ember Doctor: "
    )
    add_bullet_p(doc, 
        "If a custom component or experimental script throws an unhandled exception, the editor catches it, preserves state, displays a non-intrusive alert, and writes full diagnostics to daily log files—never tearing down your editor session.",
        bold_prefix="Isolated Error Boundaries: "
    )

    # -------------------------------------------------------------
    # SECTION 8: WHY THIS MATTERS FOR FLUTTER DEVELOPERS
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "8. Why This Matters for Every Flutter Developer")
    
    add_body_p(doc, 
        "Even if your day job isn't building AAA titles, the emergence of a native visual game engine in Flutter opens up tremendous opportunities:"
    )
    
    add_bullet_p(doc, 
        "Apps today increasingly leverage rich gamified mechanics (streaks, interactive challenges, celebratory reward animations, simulation mini-games). Ember Engine lets you build and embed rich game scenes directly without massive binary bloat.",
        bold_prefix="Gamification of Commercial Apps: "
    )
    add_bullet_p(doc, 
        "Instead of taking days to lay out physics mockups or interactive 2D/3D components, developers can visually design prototypes in minutes, test them in place, and share executables with stakeholders immediately.",
        bold_prefix="Rapid Spatial Prototyping: "
    )
    add_bullet_p(doc, 
        "By proving that Flutter can power a desktop-class IDE with real-time 3D rendering, physics simulations, and embedded scripting, Ember Engine demonstrates the incredible maturity and versatility of the Flutter framework as a whole.",
        bold_prefix="Expanding the Boundaries of Flutter: "
    )

    # -------------------------------------------------------------
    # CONCLUSION & CALL TO ACTION
    # -------------------------------------------------------------
    style_heading_1(doc.add_paragraph(), "9. Conclusion & Getting Started")
    
    add_body_p(doc, 
        "Flutter already conquered cross-platform application development. "
        "With Ember Engine, the ecosystem takes a giant leap forward into spatial creation and game design. "
        "Whether you're an indie developer looking to build your dream retro platformer, a mobile developer adding gamification to your product, or a Dart enthusiast curious about engine architecture, Ember Engine gives you the tools to create without compromise."
    )
    
    add_callout(doc, 
        "Ready to build your first game? Clone the repository, run flutter run -d windows (or macOS/Linux), select a starter template from the Project Hub, and press Play!",
        attribution="Join the Ember Engine Community"
    )
    
    style_heading_2(doc.add_paragraph(), "Quick Start in 3 Commands:")
    
    quick_start_code = """# 1. Clone & fetch dependencies
git clone https://github.com/neetoosan/EmberEngine.git
cd "EmberEngine"
flutter pub get

# 2. Launch the visual editor
flutter run -d windows   # or: -d macos / -d linux

# 3. Press Play, explore the templates, and export your game!"""
    add_code_block(doc, quick_start_code, language="Terminal / Bash")
    
    p_tags = doc.add_paragraph()
    p_tags.paragraph_format.space_before = Pt(8)
    p_tags.paragraph_format.space_after = Pt(4)
    r_tags = p_tags.add_run("#Flutter #Dart #GameDevelopment #EmberEngine #IndieDev #MobileDev #OpenSource #TechInnovation #SoftwareArchitecture")
    r_tags.font.name = "Calibri"
    r_tags.font.size = Pt(10)
    r_tags.font.bold = True
    r_tags.font.color.rgb = RGBColor(230, 81, 0)
    
    # Save the document
    output_filename = r"c:\Dev\ember engine\Ember_Engine_LinkedIn_Article.docx"
    doc.save(output_filename)
    print(f"Document successfully created at {output_filename}")
    
    # Also save a copy in docs/
    docs_copy = r"c:\Dev\ember engine\docs\Ember_Engine_LinkedIn_Article.docx"
    shutil.copyfile(output_filename, docs_copy)
    print(f"Copy saved to {docs_copy}")

if __name__ == "__main__":
    main()
