-- =============================================================================
-- Dharma Library — reference seed (idempotent)
-- Languages, scripts, app config. Content lives in /content and is loaded by
-- scripts/ingest.py (which emits SQL).
-- =============================================================================

insert into public.scripts (code, name_en, name_native, sample, sort_order) values
  ('Deva', 'Devanagari', 'देवनागरी', 'ॐ', 10),
  ('Latn', 'Latin (IAST)', 'IAST', 'oṁ', 20),
  ('Mlym', 'Malayalam', 'മലയാളം', 'ഓം', 30),
  ('Knda', 'Kannada', 'ಕನ್ನಡ', 'ಓಂ', 40),
  ('Telu', 'Telugu', 'తెలుగు', 'ఓం', 50),
  ('Taml', 'Tamil', 'தமிழ்', 'ௐ', 60),
  ('Beng', 'Bengali', 'বাংলা', 'ওঁ', 70),
  ('Gujr', 'Gujarati', 'ગુજરાતી', 'ૐ', 80),
  ('Guru', 'Gurmukhi', 'ਗੁਰਮੁਖੀ', 'ੴ', 90),
  ('Orya', 'Odia', 'ଓଡ଼ିଆ', 'ଓଁ', 100)
on conflict (code) do update set name_en = excluded.name_en, name_native = excluded.name_native, sample = excluded.sample, sort_order = excluded.sort_order;

insert into public.languages (code, name_en, name_native, default_script, is_ui_locale, sort_order) values
  ('sa', 'Sanskrit',  'संस्कृतम्', 'Deva', false, 10),
  ('en', 'English',   'English',   'Latn', true,  20),
  ('ml', 'Malayalam', 'മലയാളം',   'Mlym', true,  30),
  ('hi', 'Hindi',     'हिन्दी',    'Deva', false, 40),
  ('kn', 'Kannada',   'ಕನ್ನಡ',     'Knda', false, 50),
  ('te', 'Telugu',    'తెలుగు',    'Telu', false, 60),
  ('ta', 'Tamil',     'தமிழ்',     'Taml', false, 70),
  ('bn', 'Bengali',   'বাংলা',     'Beng', false, 80),
  ('gu', 'Gujarati',  'ગુજરાતી',   'Gujr', false, 90),
  ('pa', 'Punjabi',   'ਪੰਜਾਬੀ',    'Guru', false, 100),
  ('or', 'Odia',      'ଓଡ଼ିଆ',     'Orya', false, 110)
on conflict (code) do update set name_en = excluded.name_en, name_native = excluded.name_native,
  default_script = excluded.default_script, is_ui_locale = excluded.is_ui_locale, sort_order = excluded.sort_order;

insert into public.app_config (key, value) values
  ('min_app_version', '"0.1.0"'),
  ('features', '{"ai_qa": true, "audio": true, "offline_bundles": true, "search": true}'),
  ('default_work', '"bhagavata-purana"'),
  ('default_reader_layout', '{"en": ["sb-mula-deva", "sb-iast", "sb-en-dl"], "ml": ["sb-mula-mlym", "sb-mula-deva", "sb-ml-dl"]}'),
  ('ai_qa', '{"provider": "openai", "model": "gpt-4o-mini", "embedding_model": "text-embedding-3-small", "max_citations": 6, "refuse_without_citations": true}')
on conflict (key) do update set value = excluded.value;
