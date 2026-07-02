-- Stoma Alert — let patients edit the note on / delete their own diary photos.
-- Adds UPDATE + DELETE RLS on diary_photos and DELETE on the storage objects. SQL Editor.

drop policy if exists "update own diary photos" on public.diary_photos;
create policy "update own diary photos" on public.diary_photos for update
  to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "delete own diary photos" on public.diary_photos;
create policy "delete own diary photos" on public.diary_photos for delete
  to authenticated using (user_id = auth.uid());

drop policy if exists "diary delete own" on storage.objects;
create policy "diary delete own" on storage.objects for delete
  to authenticated using (
    bucket_id = 'diary-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
