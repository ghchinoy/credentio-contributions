import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import catppuccin from '@catppuccin/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://ghchinoy.github.io',
	base: '/credentio-contributions',
	integrations: [
		starlight({
			title: 'Credentio Contributions',
			description: 'Idiomatic Python, Go, and Swift bindings for Google Credentio C2PA Content Credentials validator',
			plugins: [
				catppuccin({
					dark: { flavor: 'mocha', accent: 'sky' },
					light: { flavor: 'latte', accent: 'sky' },
				}),
			],
			social: [
				{
					icon: 'github',
					label: 'Credentio Contributions on GitHub',
					href: 'https://github.com/ghchinoy/credentio-contributions',
				},
				{
					icon: 'external',
					label: 'Authoritative Google Credentio Source',
					href: 'https://mediaprovenance.googlesource.com/credentio/',
				},
			],
			sidebar: [
				{
					label: 'Overview',
					items: [
						{ label: 'Introduction', slug: 'index' },
						{ label: 'Why Credentio Bindings?', slug: 'why' },
						{ label: 'C2PA Core Concepts', slug: 'concepts' },
						{ label: 'Trust Anchors & Validity', slug: 'trust' },
						{ label: 'Quick Start', slug: 'getting-started' },
					],
				},
				{
					label: 'Command-Line Tools',
					items: [
						{ label: 'CLI Tutorial', slug: 'cli' },
					],
				},
				{
					label: 'Agent Ecosystem',
					items: [
						{ label: 'Agent Plugin & Skill', slug: 'agent-plugin' },
					],
				},
				{
					label: 'Language Bindings',
					items: [
						{ label: 'Python (credentio)', slug: 'python' },
						{ label: 'Go (credentio/go)', slug: 'go' },
						{ label: 'Swift (CredentioKit)', slug: 'swift' },
						{ label: 'WebAssembly (TypeScript)', slug: 'wasm' },
					],
				},
				{
					label: 'Architecture & Community',
					items: [
						{ label: 'C-ABI Architecture', slug: 'architecture' },
						{ label: 'Contributing & Upstreaming', slug: 'contributing' },
						{ label: 'Maintenance & Drift Detection', slug: 'maintenance' },
					],
				},
			],
		}),
	],
});
