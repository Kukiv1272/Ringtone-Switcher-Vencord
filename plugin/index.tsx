/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import * as DataStore from "@api/DataStore";
import { definePluginSettings, SettingsStore } from "@api/Settings";
import { Button } from "@components/Button";
import ErrorBoundary from "@components/ErrorBoundary";
import { Flex } from "@components/Flex";
import { Paragraph } from "@components/Paragraph";
import { Logger } from "@utils/Logger";
import definePlugin, { OptionType } from "@utils/types";
import { chooseFile } from "@utils/web";
import { Select, showToast, useEffect, useRef, useState } from "@webpack/common";

import { HISTORICAL_RINGTONES } from "./ringtones";

const PLUGIN_NAME = "RingtoneSwitcher";
const PRESET_SETTING = `plugins.${PLUGIN_NAME}.preset`;
const FILE_PREFIX = "RingtoneSwitcher:file:";
const MAX_FILE_MB = 50;

// Preset ids used by the first release, before the dated tracks were added.
const LEGACY_PRESETS: Record<string, string> = {
    halloween: "halloween_2025",
    winter: "christmas_2025"
};

const logger = new Logger(PLUGIN_NAME);

interface Preset {
    id: string;
    label: string;
    note: string;
    url: string;
}

const historical = (id: string, label: string, note: string): Preset => ({
    id,
    label,
    note,
    url: HISTORICAL_RINGTONES[id]
});

// One entry per distinct ringtone Discord shipped: some years reuse the same track.
const PRESETS: Preset[] = [
    historical("classic", "Classic", "Discord's original ringtone."),
    historical("halloween_2020_2021", "Halloween 2020–2021", "Halloween event ringtone."),
    historical("halloween_2022", "Halloween 2022", "Halloween event ringtone."),
    historical("halloween_2023", "Halloween 2023", "Halloween event ringtone."),
    historical("halloween_2024", "Halloween 2024", "Halloween event ringtone."),
    historical("halloween_2025", "Halloween 2025", "Halloween event ringtone."),
    historical("christmas_2021", "Christmas 2021", "Winter event ringtone."),
    historical("christmas_2022_2023", "Christmas 2022–2023", "Winter event ringtone."),
    historical("christmas_2024", "Christmas 2024", "Winter event ringtone."),
    historical("christmas_2025", "Christmas 2025", "Winter event ringtone.")
];

interface StoredRingtone {
    name: string;
    addedAt: number;
    file: File;
}

interface SavedRingtone {
    id: string;
    name: string;
    addedAt: number;
}

const fileKey = (id: string) => FILE_PREFIX + id;

let activeFileId: string | undefined;
let activeUrl: string | undefined;
let loadGeneration = 0;
let previewAudio: HTMLAudioElement | undefined;

function findPreset(preset: string) {
    return PRESETS.find(p => p.id === preset);
}

function getPresetUrl(preset: string) {
    return findPreset(preset)?.url;
}

export function getActiveSrc() {
    const preset: string = settings.store.preset ?? "default";

    if (preset.startsWith("custom:")) return activeUrl;
    return getPresetUrl(preset);
}

async function applyActiveFile() {
    const preset: string = settings.store.preset ?? "default";
    const id = preset.startsWith("custom:") ? preset.slice("custom:".length) : undefined;
    const generation = ++loadGeneration;

    if (id === activeFileId && (id === undefined || activeUrl)) return;

    if (activeUrl) URL.revokeObjectURL(activeUrl);
    activeUrl = undefined;
    activeFileId = id;

    if (!id) return;

    try {
        const stored = await DataStore.get<StoredRingtone>(fileKey(id));
        if (generation !== loadGeneration) return;

        if (stored?.file instanceof Blob && stored.file.size > 0) {
            activeUrl = URL.createObjectURL(stored.file);
        }
    } catch (e) {
        logger.error("Failed to load the selected ringtone:", e);
    }
}

async function listRingtones(): Promise<SavedRingtone[]> {
    const keys = (await DataStore.keys()).filter((key): key is string => typeof key === "string" && key.startsWith(FILE_PREFIX));
    const values = await DataStore.getMany<StoredRingtone | undefined>(keys);

    return keys
        .flatMap((key, i) => {
            const value = values[i];
            if (!value?.file) return [];

            return {
                id: key.slice(FILE_PREFIX.length),
                name: value.name || "Unnamed",
                addedAt: value.addedAt || 0
            };
        })
        .sort((a, b) => a.addedAt - b.addedAt);
}

async function addRingtone(file: File) {
    if (!file.size) throw new Error("The file is empty");
    if (file.size > MAX_FILE_MB * 1024 * 1024) throw new Error(`The file is larger than ${MAX_FILE_MB} MB`);

    const id = crypto.randomUUID();
    await DataStore.set(fileKey(id), {
        name: file.name,
        addedAt: Date.now(),
        file
    } satisfies StoredRingtone);

    settings.store.preset = `custom:${id}`;
    await applyActiveFile();
}

async function removeRingtone(id: string) {
    await DataStore.del(fileKey(id));

    if (settings.store.preset === `custom:${id}`) {
        settings.store.preset = "default";
        await applyActiveFile();
    }
}

function stopPreview() {
    previewAudio?.pause();
    previewAudio = undefined;
}

const RingtoneSettings = ErrorBoundary.wrap(function RingtoneSettings() {
    const { preset: storedPreset } = settings.use(["preset"]);
    const preset: string = storedPreset ?? "default";
    const [files, setFiles] = useState<SavedRingtone[]>([]);
    const [previewing, setPreviewing] = useState(false);
    const previewUrl = useRef<string | undefined>(undefined);

    const refresh = () => {
        listRingtones()
            .then(setFiles)
            .catch(e => logger.error("Failed to list ringtones:", e));
    };

    const clearPreviewUrl = () => {
        if (!previewUrl.current) return;
        URL.revokeObjectURL(previewUrl.current);
        previewUrl.current = undefined;
    };

    useEffect(refresh, []);

    useEffect(() => {
        stopPreview();
        setPreviewing(false);
        clearPreviewUrl();
    }, [preset]);

    useEffect(() => () => {
        stopPreview();
        clearPreviewUrl();
    }, []);

    async function togglePreview() {
        if (previewAudio) {
            stopPreview();
            setPreviewing(false);
            clearPreviewUrl();
            return;
        }

        await applyActiveFile();

        let src = getActiveSrc();
        if (!src && preset.startsWith("custom:")) {
            const stored = await DataStore.get<StoredRingtone>(fileKey(preset.slice("custom:".length)));
            if (stored?.file instanceof Blob) {
                src = URL.createObjectURL(stored.file);
                previewUrl.current = src;
            }
        }

        if (!src) {
            showToast({ text: "The Discord default ringtone can't be previewed", variant: "critical" });
            return;
        }

        const audio = new Audio(src);
        previewAudio = audio;
        audio.onended = () => {
            if (previewAudio === audio) previewAudio = undefined;
            setPreviewing(false);
            clearPreviewUrl();
        };
        audio.onerror = () => {
            if (previewAudio === audio) previewAudio = undefined;
            setPreviewing(false);
            clearPreviewUrl();
            showToast({ text: "Failed to play this ringtone", variant: "critical" });
        };

        try {
            await audio.play();
            setPreviewing(true);
        } catch (e) {
            logger.error("Failed to preview the ringtone:", e);
            stopPreview();
            setPreviewing(false);
        }
    }

    async function pickFile() {
        const file = await chooseFile("audio/*");
        if (!file) return;

        try {
            await addRingtone(file);
            refresh();
        } catch (e) {
            showToast({ text: e instanceof Error ? e.message : "Failed to add the ringtone", variant: "critical" });
        }
    }

    const selectedFileId = preset.startsWith("custom:") ? preset.slice("custom:".length) : undefined;
    const selectedPreset = findPreset(preset);
    const options = [
        { label: "Default — Discord decides (no override)", value: "default" },
        ...PRESETS.map(({ id, label }) => ({ label, value: id })),
        ...files.map(file => ({ label: `Custom — ${file.name}`, value: `custom:${file.id}` }))
    ];

    return (
        <div>
            <Select
                options={options}
                maxVisibleItems={7}
                closeOnSelect={true}
                select={value => settings.store.preset = value}
                isSelected={value => value === preset}
                serialize={value => String(value)}
                placeholder="Choose a ringtone"
            />

            {selectedPreset && (
                <Paragraph style={{ marginTop: "0.5em" }}>{selectedPreset.note}</Paragraph>
            )}

            <Flex gap="0.5em" style={{ marginTop: "0.75em" }} flexWrap="wrap">
                <Button size="small" onClick={pickFile}>Add custom file…</Button>
                <Button
                    size="small"
                    variant="secondary"
                    disabled={preset === "default"}
                    onClick={togglePreview}
                >
                    {previewing ? "Stop" : "Preview"}
                </Button>
                <Button
                    size="small"
                    variant="dangerSecondary"
                    disabled={!selectedFileId}
                    onClick={async () => {
                        if (!selectedFileId) return;
                        try {
                            await removeRingtone(selectedFileId);
                        } catch (e) {
                            logger.error("Failed to delete the ringtone:", e);
                            showToast({ text: "Failed to delete the ringtone", variant: "critical" });
                        }
                        refresh();
                    }}
                >
                    Delete
                </Button>
            </Flex>

            <Paragraph style={{ marginTop: "0.75em" }}>
                Custom files are stored locally on this device. Every built-in ringtone is bundled with the plugin,
                so nothing is downloaded at runtime.
            </Paragraph>
        </div>
    );
}, { noop: false });

const settings = definePluginSettings({
    preset: {
        type: OptionType.STRING,
        description: "The selected ringtone",
        default: "default",
        hidden: true
    },
    picker: {
        type: OptionType.COMPONENT,
        component: RingtoneSettings
    }
});

export default definePlugin({
    name: PLUGIN_NAME,
    description: "Switch Discord's incoming call ringtone: choose a built-in variant or use your own audio file",
    tags: ["Notifications", "Customisation"],
    searchTerms: ["ringtone", "sound", "call", "audio"],
    authors: [{ name: "kukiv1272", id: 0n }],
    settings,

    patches: [{
        // WebAudioSound.ensureAudio: audio.src = require(`./${this.name}.mp3`)
        find: "could not play audio:",
        replacement: {
            match: /(\i\.src=)(.{0,30}?)\((?:`\.\/\$\{this\.name\}\.(\w+)`|"\.\/"\.concat\(this\.name,"\.(\w+)"\))\)/,
            replace: "$1$self.resolveSrc(this,($2),\"$3$4\")"
        }
    }],

    resolveSrc(player: { name?: string; }, req: (path: string) => string, ext?: string) {
        const { name } = player;

        if (typeof name === "string" && name.includes("call_ringing")) {
            try {
                const src = getActiveSrc();
                if (src) return src;
            } catch (e) {
                logger.error("Failed to get the selected ringtone:", e);
            }
        }

        return req(`./${name}.${ext || "mp3"}`);
    },

    async start() {
        const preset: string = settings.store.preset ?? "default";
        if (preset in LEGACY_PRESETS) {
            settings.store.preset = LEGACY_PRESETS[preset];
        } else if (preset !== "default" && !preset.startsWith("custom:") && !findPreset(preset)) {
            settings.store.preset = "default";
        }

        await applyActiveFile();
        SettingsStore.addChangeListener(PRESET_SETTING, applyActiveFile);
    },

    stop() {
        SettingsStore.removeChangeListener(PRESET_SETTING, applyActiveFile);
        stopPreview();

        if (activeUrl) URL.revokeObjectURL(activeUrl);
        activeUrl = undefined;
        activeFileId = undefined;
    }
});
