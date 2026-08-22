import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'Credentio Contributions',
			description: 'Idiomatic Python and Go bindings for Google Credentio C2PA Content Credentials validator',
			social: {
				github: 'https://mediaprovenance.googlesource.com/credentio/',
			},
			sidebar: [
				{
					label: 'Overview',
					items: [
						{ label: 'Introduction', slug: 'index' },
						{ label: 'Why Credentio Bindings?', slug: 'why' },
						{ label: 'C2PA Core Concepts', slug: 'concepts' },
						{ label: 'Quick Start', slug: 'getting-started' },
					],
				},
				{
					label: 'Language Bindings',
					items: [
						{ label: 'Python (credentio)', slug: 'python' },
						{ label: 'Go (github.com/google/credentio/go)', slug: 'go' },
						{ label: 'Swift (CredentioKit)', slug: 'swift' },
					],
				},
				{
					label: 'Architecture & Community',
					items: [
						{ label: 'C-ABI Architecture', slug: 'architecture' },
						{ label: 'Contributing & Upstreaming', slug: 'contributing' },
					],
				},
			],
		}),
	],
});
