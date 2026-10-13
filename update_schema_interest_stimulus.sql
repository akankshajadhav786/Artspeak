-- ==============================================================================
-- ArtSpeak Schema Update: Interest Stimulus & LLM Detailed Report
-- ==============================================================================

-- 1. Add stimulus tracking to sessions
alter table public.sessions
  add column if not exists stimulus_category text check (stimulus_category in ('animals', 'nature', 'objects', 'people')),
  add column if not exists stimulus_image_id text,
  add column if not exists stimulus_duration_seconds integer not null default 10;

-- 2. Add stimulus reaction and LLM detailed analysis to session_reports
alter table public.session_reports
  add column if not exists stimulus_category text,
  add column if not exists stimulus_image_id text,
  add column if not exists stimulus_reaction_summary text,
  add column if not exists simple_language_report text;

-- 3. Add facial prediction stimulus phase flag
alter table public.predictions_facial_emotion
  add column if not exists phase text default 'drawing' check (phase in ('stimulus', 'drawing', 'full'));

-- 4. Create index for analytics on interest categories
create index if not exists idx_sessions_stimulus_cat on public.sessions(stimulus_category);
