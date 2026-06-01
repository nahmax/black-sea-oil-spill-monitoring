-- ==========================================
-- Схема БД для моніторингу розливів нафти / палива
-- Чорне / Азовське море + RAG + Telegram
-- ==========================================

-- Розширення pgvector для зберігання ембедінгів
CREATE EXTENSION IF NOT EXISTS vector;

-- ==========================================
-- Функція хешування події
-- використовується у WF_NEWS_ON_DEMAND та WF_EVENT_UPSERT_MANUAL
-- ==========================================
CREATE OR REPLACE FUNCTION public.compute_event_hash(
  p_src_url          text,
  p_src_title        text,
  p_src_published_at timestamptz
)
RETURNS text
LANGUAGE sql
AS $$
  -- Проста схема: md5 від (url | title | published_at)
  SELECT md5(
    coalesce(p_src_url, '') || '|' ||
    coalesce(p_src_title, '') || '|' ||
    coalesce(p_src_published_at::text, '')
  );
$$;

-- ==========================================
-- Таблиця подій public.events
-- основна сутність для всіх воркфлоу
-- ==========================================
CREATE TABLE public.events (
  id               bigserial PRIMARY KEY,      -- внутрішній ID події

  -- Поля джерела новини
  src_title        text,                       -- заголовок новини / статті
  src_url          text,                       -- URL на джерело
  src_source       text,                       -- тип джерела ('manual', 'gpt_search', тощо)
  src_lang         text,                       -- мова джерела ('uk', 'en', 'ru'...)

  src_published_at timestamptz,                -- коли опублікована новина (час джерела)
  event_date       date,                       -- реальна дата інциденту (може відрізнятися від публікації)

  -- Короткий опис події
  short_summary    text,                       -- стисле резюме події українською

  -- Географія
  lat              double precision,           -- широта центру плями/події
  lon              double precision,           -- довгота центру плями/події

  -- Класифікація / статус події
  is_oil_black_sea boolean,                    -- чи це реальний розлив у Чорному/Азовському морі
  verdict          text,                       -- вердикт детектора по супутниковому знімку: 'spill' | 'skip' | 'unknown'
  confidence       double precision,           -- впевненість детектора (0..1)
  has_photo        boolean DEFAULT false,      -- чи вже є супутниковий знімок (Sentinel-1) у Telegram
  s1_date          timestamptz,                -- дата S1 знімка (якщо зберігаєш окремо)

  -- LLM метадані
  llm_extract      jsonb,                      -- сирі JSON-витяги від LLM (класифікація, координати тощо)
  llm_version      text,                       -- версія моделі, яка останньою оновлювала llm_extract/verdict

  -- Вектор для RAG / семантичного пошуку
  title_emb        vector(1536),               -- ембедінг заголовку+summary (text-embedding‑3‑small)

  -- Унікальний хеш події
  hash             text NOT NULL UNIQUE        -- використовується для ON CONFLICT (hash)
);

-- Індекс по прапору, щоб швидко діставати лише релевантні події
CREATE INDEX IF NOT EXISTS events_is_oil_black_sea_idx
  ON public.events (is_oil_black_sea);

-- Векторний індекс (approximate nearest neighbors) під запити типу
-- ORDER BY title_emb <=> $1::vector LIMIT 10;
CREATE INDEX IF NOT EXISTS events_title_emb_ivfflat_idx
  ON public.events USING ivfflat (title_emb vector_cosine_ops)
  WITH (lists = 100);

-- ==========================================
-- Користувачі Telegram‑бота
-- використовується в AGENT_CHAT_BOT (PG.GET_USER)
-- ==========================================
CREATE TABLE public.users (
  id         bigserial PRIMARY KEY,            -- внутрішній ID користувача
  tg_user_id text    NOT NULL,                 -- Telegram user id (як рядок)
  role       text    NOT NULL DEFAULT 'user',  -- роль: 'user', 'admin' тощо
  status     text    NOT NULL DEFAULT 'active',-- статус: 'active', 'blocked' і т.п.
  created_at timestamptz NOT NULL DEFAULT now()-- коли користувача вперше побачили
);

-- Один Telegram‑аккаунт = один запис в таблиці users
CREATE UNIQUE INDEX IF NOT EXISTS users_tg_user_id_uniq
  ON public.users (tg_user_id);

-- ==========================================
-- Налаштування агента
-- (звідси береться канал для постів, ключі та інші параметри)
-- ==========================================
CREATE TABLE public.agent_settings (
  key        text  PRIMARY KEY,                -- назва налаштування (наприклад 'channel')
  value      jsonb NOT NULL,                   -- довільний JSON з конфігом
  updated_at timestamptz NOT NULL DEFAULT now()-- коли останній раз змінювали
);

-- Приклад заповнення каналу (ЗАМІНИ '@your_channel_here' на свій):
-- INSERT INTO public.agent_settings(key, value)
-- VALUES (
--   'channel',
--   jsonb_build_object('id', '@your_channel_here')
-- )
-- ON CONFLICT (key) DO UPDATE
--   SET value = EXCLUDED.value,
--       updated_at = now();

-- ==========================================
-- Прив’язка подій до постів у Telegram‑каналі
-- використовується в WF_EVENT_PUBLISH_AGENT, WF_EVENT_S1_AGENT, WF_EVENT_S1_AGENT
-- ==========================================
CREATE TABLE public.tg_posts (
  event_id   bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE, -- ID події
  channel_id text   NOT NULL,                                               -- ID/юзернейм каналу
  message_id bigint NOT NULL,                                               -- message_id поста в каналі
  created_at timestamptz NOT NULL DEFAULT now(),                            -- коли створили/оновили
  PRIMARY KEY (event_id, channel_id)                                        -- для ON CONFLICT (event_id, channel_id)
);

CREATE INDEX IF NOT EXISTS tg_posts_message_id_idx
  ON public.tg_posts (message_id);

-- ==========================================
-- Медіа з Telegram (супутникові знімки тощо)
-- використовується в WF_EVENT_S1_AGENT та WF_EVENT_DET_AGENT
-- ==========================================
CREATE TABLE public.tg_media (
  id         bigserial PRIMARY KEY,             -- внутрішній ID медіа
  event_id   bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE, -- до якої події належить
  message_id bigint NOT NULL,                   -- message_id повідомлення з медіа
  file_id    text   NOT NULL,                   -- Telegram file_id
  kind       text   NOT NULL,                   -- тип медіа ('document', 'photo' тощо)
  created_at timestamptz NOT NULL DEFAULT now() -- коли зберегли
);

-- Унікальність комбінації event/message/file для ON CONFLICT DO NOTHING
CREATE UNIQUE INDEX IF NOT EXISTS tg_media_unique_file_idx
  ON public.tg_media (event_id, message_id, file_id);

CREATE INDEX IF NOT EXISTS tg_media_event_id_idx
  ON public.tg_media (event_id);

-- ==========================================
-- Таблиця доказів (evidence) від моделей/людей
-- використовується в WF_EVENT_DET_AGENT
-- ==========================================
CREATE TABLE public.evidence (
  id            bigserial PRIMARY KEY,             -- внутрішній ID запису
  event_id      bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE, -- пов’язана подія
  evidence_type text   NOT NULL,                  -- тип ('satellite', 'text', 'manual', ...)
  provider      text,                              -- хто надав: 'openai:gpt-4.1-mini', 'expert', ...
  url           text,                              -- посилання на джерело (якщо є)
  snippet       text,                              -- короткий уривок / пояснення українською
  created_at    timestamptz NOT NULL DEFAULT now() -- коли додали доказ
);

CREATE INDEX IF NOT EXISTS evidence_event_id_idx
  ON public.evidence (event_id);
