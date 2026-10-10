// Run with node scripts/check-theme-contrast.cjs; --write-doc updates the checked-in ratio table.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('LiquidGlassMessaging/DesignSystem/ThemePalette.swift', 'utf8');
const definitions = [...source.matchAll(/return ThemePalette\(isLight: (true|false), base: (0x\w+),\s*mesh: \[([^\]]+)\],\s*accent: (0x\w+), success: (0x\w+), destructive: (0x\w+), warning: (0x\w+)\)/g)];
assert.equal(definitions.length, 3, 'Every production theme must be checked');
const names = ['Onyx', 'Aurora', 'Daylight'];
const channels = h => [h >> 16 & 255, h >> 8 & 255, h & 255];
const hex = a => (a[0] << 16) | (a[1] << 8) | a[2];
const code = h => '#' + h.toString(16).padStart(6, '0').toUpperCase();
const luminance = h => channels(h).map(c => { c /= 255; return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4; }).reduce((sum, c, i) => sum + c * [.2126, .7152, .0722][i], 0);
const contrast = (a, b) => (Math.max(luminance(a), luminance(b)) + .05) / (Math.min(luminance(a), luminance(b)) + .05);
const composite = (fg, bg, alpha) => hex(channels(fg).map((c, i) => Math.round(c * alpha + channels(bg)[i] * (1 - alpha))));
let table = '| Theme | Token pair (minimum over tested backgrounds) | Ratio | Threshold | Result |\n|---|---|---:|---:|---|\n';
for (const [index, match] of definitions.entries()) {
  const light = match[1] === 'true', base = +match[2];
  const backgrounds = [base, ...match[3].split(',').map(c => +c.trim())];
  const envelope = hex([0, 1, 2].map(i => (light ? Math.min : Math.max)(...backgrounds.map(b => channels(b)[i]))));
  const wallpaper = composite(base, light ? 0 : 0xffffff, .96);
  // Include all vertices, the conservative component envelope, and arbitrary photos under scrim.
  const samples = [...backgrounds, envelope, wallpaper];
  const text = light ? 0 : 0xffffff;
  const supporting = light ? text : 0xebebf5;
  const supportingAlpha = light ? 1 : .6;
  const tokens = [
    ['primary / backdrop', b => contrast(text, b), 4.5],
    ['supporting / backdrop', b => contrast(composite(supporting, b, supportingAlpha), b), 4.5],
    ...['accent', 'success', 'destructive', 'warning'].map((name, i) => [name + ' / backdrop', b => contrast(+match[4 + i], b), 4.5])
  ];
  for (const [name, ratioFor, threshold] of tokens) {
    const ratio = Math.min(...samples.map(ratioFor));
    assert.ok(ratio >= threshold, `${names[index]} ${name}: ${ratio}`);
    table += `| ${names[index]} | ${name} | ${ratio.toFixed(2)}:1 | ${threshold}:1 | PASS |\n`;
  }
  console.log(names[index], 'base', code(base), 'envelope', code(envelope));
}
console.log(table);
const document = `# Theme contrast\n\nProduction colors are centralized in ThemePalette.swift. Run \`node scripts/check-theme-contrast.cjs --write-doc\` to regenerate this table from those definitions.\n\nWCAG ratios use sRGB linearization and (Llighter + 0.05) / (Ldarker + 0.05). Every base, every mesh vertex, the conservative RGB component envelope, and the worst arbitrary wallpaper after the 96% scheme-aware scrim are checked. Smooth color interpolation is disabled to prevent cubic overshoot. Status and accent tokens pass 4.5:1 because they also appear in small text; this exceeds the 3:1 UI requirement.\n\n${table}\nSupporting text uses semantic primary in Daylight and semantic secondary in dark themes. Standard light secondary text was only about 3.15:1 over these backgrounds, so it is deliberately not used. The smallest passing ratio is Aurora supporting text; keep mesh luminance restrained.\n\nThe portable checker uses reference label components (dark primary FFFFFF, dark secondary EBEBF5 at 60%, light primary 000000). These are verification inputs, never hard-coded UI text. The hostless ThemeContrastTests target resolves actual UIKit label/secondaryLabel colors on the selected iOS 26 simulator and checks the same backgrounds, plus migration and Onyx invariants. CI runs both the portable check and XCTest, then archives the app.\n\nThese numbers certify the palette/backdrop contract, not rendered pixels: SwiftUI semantic styles, vibrant text, native regular glass, tint adaptation, native prominent button labels, accessibility settings, arbitrary media and system dialogs are composited by Apple. Screens were audited in code; visual verification of every screen on an iOS 26 device/simulator is still required. Do not claim these arithmetic tests certify all rendered glass surfaces.\n\nReviewed screens: Settings root/profile and all five sub-pages; Home; Messages/search/contacts/chat cards; alternate room list and floating tab bar; chat header/composer/bubbles/typing indicator; authentication; call tiles/controls; live console; Add Contact/New Group/Archived sheets; full-screen media and cache confirmation dialog.\n\nNo Materials, blur effects, artificial glass strokes/shadows, or opaque UI contrast patches are used. Solid base colors and swatch gradients are background/preview content. Status dots are meaningful colored indicators. Text-heavy surfaces use native regular glass; prominent buttons keep system-controlled label styling.\n\nApple API references: [MeshGradient initializer](https://developer.apple.com/documentation/swiftui/meshgradient/init(width:height:points:colors:background:smoothscolors:colorspace:)), [preferredColorScheme](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)), [tint](https://developer.apple.com/documentation/swiftui/view/tint(_:)), [Glass](https://developer.apple.com/documentation/swiftui/glass), [SwiftUI and Liquid Glass WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/). MeshGradient requires iOS 18; Liquid Glass requires iOS 26, matching project.yml.\n`;
if (process.argv.includes('--write-doc')) fs.writeFileSync('docs/ThemeContrast.md', document);
else assert.equal(fs.readFileSync('docs/ThemeContrast.md', 'utf8'), document, 'Regenerate docs/ThemeContrast.md after palette changes');
