-- Storage RLS. Convention: every object path is "{auth.uid()}/filename",
-- so the owner is the first path segment — mirrors an owner-scoped
-- MEDIA_ROOT subfolder without needing a lookup table.

create or replace function public.owns_storage_path(object_name text) returns boolean
language sql stable as $$
  select (storage.foldername(object_name))[1] = auth.uid()::text
$$;

-- Private buckets: owner read/write own folder, admin reads everything.
do $$
declare b text;
begin
  foreach b in array array['kyc-documents','vehicle-photos','dump-report-photos','investor-id-cards']
  loop
    execute format($p$
      create policy "%1$s_owner_all" on storage.objects for all
        using (bucket_id = '%1$s' and (public.owns_storage_path(name) or public.is_admin()))
        with check (bucket_id = '%1$s' and public.owns_storage_path(name));
    $p$, b);
  end loop;
end $$;

-- profile-images: public bucket (served via public URL), but writes are
-- still owner-scoped through the API.
create policy "profile_images_public_read" on storage.objects for select
  using (bucket_id = 'profile-images');
create policy "profile_images_owner_write" on storage.objects for insert
  with check (bucket_id = 'profile-images' and public.owns_storage_path(name));
create policy "profile_images_owner_update" on storage.objects for update
  using (bucket_id = 'profile-images' and public.owns_storage_path(name));
create policy "profile_images_owner_delete" on storage.objects for delete
  using (bucket_id = 'profile-images' and public.owns_storage_path(name));
