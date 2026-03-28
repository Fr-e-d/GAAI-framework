#!/usr/bin/env node
/**
 * Check if skills index is stale and regenerate if needed
 *
 * Usage:
 *   node check-and-update-skills-index.js
 *   Returns: 0 if index is current, 1 if regenerated
 */

const fs = require('fs');
const path = require('path');

function getFileModTime(filePath) {
    try {
        return fs.statSync(filePath).mtimeMs;
    } catch {
        return 0;
    }
}

function collectSkillFiles(dir) {
    const files = [];

    function walkDir(dirPath) {
        try {
            const entries = fs.readdirSync(dirPath);
            for (const entry of entries) {
                const fullPath = path.join(dirPath, entry);
                const stat = fs.statSync(fullPath);

                if (stat.isDirectory()) {
                    walkDir(fullPath);
                } else if (entry === 'SKILL.md') {
                    files.push(fullPath);
                }
            }
        } catch (e) {
            // Silently skip unreadable directories
        }
    }

    walkDir(dir);
    return files;
}

function isIndexStale() {
    const coreIndexPath = '.gaai/core/skills/skills-index.yaml';
    const projectIndexPath = '.gaai/project/skills/skills-index.yaml';
    const coreIndexMtime = getFileModTime(coreIndexPath);
    const projectIndexMtime = getFileModTime(projectIndexPath);

    if (!fs.existsSync(coreIndexPath)) {
        console.log('⚠️  Core index file not found');
        return true;
    }

    // Check core SKILL.md files against core index
    const coreSkillFiles = collectSkillFiles('.gaai/core/skills');
    for (const skillFile of coreSkillFiles) {
        if (getFileModTime(skillFile) > coreIndexMtime) {
            console.log(`ℹ️  Detected modification: ${skillFile}`);
            return true;
        }
    }

    // Check project SKILL.md files against project index (if project dir exists)
    if (fs.existsSync('.gaai/project/skills')) {
        const projectSkillFiles = collectSkillFiles('.gaai/project/skills');
        for (const skillFile of projectSkillFiles) {
            if (getFileModTime(skillFile) > projectIndexMtime) {
                console.log(`ℹ️  Detected modification: ${skillFile}`);
                return true;
            }
        }
    }

    return false;
}

function extractFrontmatter(filePath) {
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        const match = content.match(/^---\n([\s\S]*?)\n---/);
        if (!match) return null;

        const fm = {};
        const fmText = match[1];
        const lines = fmText.split('\n');

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.trim() === '') continue;

            if (line.startsWith('tags:')) {
                const inline = line.substring(5).trim();
                if (inline.startsWith('[')) {
                    const tagsStr = inline.slice(1, -1);
                    fm.tags = tagsStr.split(',').map(t => t.trim()).filter(t => t);
                } else {
                    const tags = [];
                    i++;
                    while (i < lines.length && lines[i].startsWith('  - ')) {
                        tags.push(lines[i].substring(4).trim());
                        i++;
                    }
                    i--;
                    fm.tags = tags;
                }
                continue;
            }

            const colonIdx = line.indexOf(':');
            if (colonIdx > 0) {
                const key = line.substring(0, colonIdx).trim();
                let value = line.substring(colonIdx + 1).trim();
                value = value.replace(/^["']|["']$/g, '');
                if (!key.startsWith(' ')) {
                    fm[key] = value;
                }
            }
        }

        if (!fm.tags) fm.tags = [];
        return fm;
    } catch (e) {
        return null;
    }
}

function scanSkills(dir, source) {
    const skills = [];

    function walkDir(dirPath) {
        try {
            const files = fs.readdirSync(dirPath);
            for (const file of files) {
                const fullPath = path.join(dirPath, file);
                const stat = fs.statSync(fullPath);

                if (stat.isDirectory()) {
                    walkDir(fullPath);
                } else if (file === 'SKILL.md') {
                    const fm = extractFrontmatter(fullPath);
                    if (fm) {
                        const skillName = path.basename(path.dirname(fullPath));
                        const relPath = fullPath.replace(/\\/g, '/').replace(/\.gaai\//g, '');

                        skills.push({
                            id: fm.id || '',
                            name: skillName,
                            source: source,
                            description: fm.description || '',
                            category: fm.category || '',
                            track: fm.track || 'cross-cutting',
                            tags: Array.isArray(fm.tags) ? fm.tags : [],
                            updated_at: fm.updated_at || new Date().toISOString().split('T')[0],
                            path: relPath
                        });
                    }
                }
            }
        } catch (e) {
            // Silently skip unreadable directories
        }
    }

    walkDir(dir);
    return skills;
}

function generateYaml(skills, header, comment) {
    const now = new Date().toISOString().split('T')[0];

    // Group by track
    const grouped = { discovery: [], delivery: [], cross: [] };
    for (const skill of skills) {
        let track = skill.track;
        if (track.includes('discovery')) track = 'discovery';
        else if (track.includes('delivery')) track = 'delivery';
        else track = 'cross';
        grouped[track].push(skill);
    }

    // Sort within each group
    for (const track of Object.keys(grouped)) {
        grouped[track].sort((a, b) => a.name.localeCompare(b.name));
    }

    let yaml = `# ${header}\n`;
    yaml += `# ${comment}\n`;
    yaml += '# Regenerate: invoke build-skills-index skill\n\n';
    yaml += `generated_at: ${now}\n`;
    yaml += `total: ${skills.length}\n\n`;

    for (const track of ['discovery', 'delivery', 'cross']) {
        if (grouped[track].length === 0) continue;
        yaml += `${track}:\n`;
        for (const skill of grouped[track]) {
            yaml += `  - id: ${skill.id}\n`;
            yaml += `    name: ${skill.name}\n`;
            yaml += `    source: ${skill.source}\n`;
            yaml += `    description: "${skill.description}"\n`;
            yaml += `    category: ${skill.category}\n`;
            yaml += `    track: ${skill.track}\n`;
            const tagsStr = skill.tags.length > 0 ? skill.tags.join(', ') : '';
            yaml += `    tags: [${tagsStr}]\n`;
            yaml += `    updated_at: ${skill.updated_at}\n`;
            yaml += `    path: ${skill.path}\n`;
        }
        yaml += '\n';
    }
    return yaml;
}

function regenerateIndex() {
    console.log('🔄 Regenerating skills indices...');

    const coreSkills = scanSkills('.gaai/core/skills', 'core');

    // Core index — core skills only (ships with OSS framework)
    const coreIndexPath = '.gaai/core/skills/skills-index.yaml';
    const coreYaml = generateYaml(
        coreSkills,
        'GAAI Core Skills Index',
        'Source of truth: .gaai/core/skills/*/SKILL.md — core framework skills only'
    );
    fs.writeFileSync(coreIndexPath, coreYaml);
    console.log(`✅ Core index: ${coreSkills.length} skills → ${coreIndexPath}`);

    // Project index — project skills only (if project dir exists)
    const projectSkillsDir = '.gaai/project/skills';
    if (fs.existsSync(projectSkillsDir)) {
        const projectSkills = scanSkills(projectSkillsDir, 'project');
        const projectIndexPath = '.gaai/project/skills/skills-index.yaml';
        const projectYaml = generateYaml(
            projectSkills,
            'GAAI Project Skills Index',
            'Source of truth: .gaai/project/skills/*/SKILL.md — project-specific skills only'
        );
        fs.writeFileSync(projectIndexPath, projectYaml);
        console.log(`✅ Project index: ${projectSkills.length} skills → ${projectIndexPath}`);
    }

    return true;
}

// Main
if (isIndexStale()) {
    regenerateIndex();
    process.exit(1); // Signal that index was regenerated
} else {
    console.log('✅ Skills index is current');
    process.exit(0); // Index was already current
}
