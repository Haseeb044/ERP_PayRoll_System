-- Run this in your Supabase SQL Editor

-- 1. Add fields to track if fine was paid to government
ALTER TABLE public.traffic_fines 
ADD COLUMN IF NOT EXISTS paid_to_govt_date TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS paid_to_govt_drawer UUID REFERENCES public.drawer(id),
ADD COLUMN IF NOT EXISTS paid_to_govt_journal_id UUID REFERENCES public.journals(id);

-- Optional: If you want to see standard fines on the UI immediately,
-- you don't need to update existing ones, they will implicitly be "unpaid".
