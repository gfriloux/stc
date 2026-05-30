import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  integrations: [
    starlight({
      title: 'STC',
      tagline: 'Standard Template Construct',
      description:
        'The sacred repository of the Adeptus Technicus — a Nix module library for the discerning Techpriest.',
      logo: {
        alt: 'Adeptus Mechanicus Cog',
        src: './src/assets/stc-logo.svg',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/gfriloux/stc',
        },
      ],
      defaultLocale: 'en',
      locales: {
        en: {
          label: 'English',
          lang: 'en',
        },
        fr: {
          label: 'Français',
          lang: 'fr',
        },
      },
      sidebar: [
        {
          label: 'The Archivum',
          translations: { fr: "L'Archivum" },
          items: [
            { slug: 'index' },
            { slug: 'getting-started' },
            { slug: 'architecture' },
          ],
        },
        {
          label: 'Relics',
          translations: { fr: 'Reliques' },
          collapsed: false,
          autogenerate: { directory: 'relics' },
        },
        {
          label: 'Cogitator',
          collapsed: false,
          autogenerate: { directory: 'cogitator' },
        },
        {
          label: 'Forge',
          translations: { fr: 'La Forge' },
          collapsed: false,
          autogenerate: { directory: 'forge' },
        },
        {
          label: 'Schematics',
          translations: { fr: 'Schémas' },
          collapsed: true,
          autogenerate: { directory: 'schematics' },
        },
      ],
      customCss: ['./src/styles/stc.css'],
    }),
  ],
});
