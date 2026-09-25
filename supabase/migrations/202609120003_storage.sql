begin;
-- Políticas permissivas existentes poderiam somar acesso via OR e anular o isolamento.
-- Não remover regras de outros projetos automaticamente: exigir revisão antes de aplicar.
do $$ begin
  if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects') then
    raise exception 'Storage já possui políticas: revisar antes de instalar o isolamento multitenant';
  end if;
end $$;
-- Privados por padrão. Exposição de imagens públicas será implementada com a página pública.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
  ('logos','logos',false,5242880,array['image/jpeg','image/png','image/webp']),
  ('covers','covers',false,10485760,array['image/jpeg','image/png','image/webp']),
  ('professionals','professionals',false,5242880,array['image/jpeg','image/png','image/webp']),
  ('service-images','service-images',false,5242880,array['image/jpeg','image/png','image/webp']);
create function private.can_manage_image(bucket text, object_name text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare tenant uuid; folder text;
begin
  if bucket not in ('logos','covers','professionals','service-images') then return false; end if;
  folder := split_part(object_name,'/',1);
  if folder !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    or object_name not like '%/_%' or object_name ~ '(^|/)\.\.?(/|$)' then return false; end if;
  tenant := folder::uuid;
  return private.has_role(tenant,case when bucket in ('logos','covers')
    then array['owner']::public.member_role[] else array['owner','manager']::public.member_role[] end);
end $$;
grant execute on function private.can_manage_image(text,text) to authenticated;
revoke execute on function private.can_manage_image(text,text) from public, anon;
create policy tenant_images_select on storage.objects for select to authenticated
  using (private.can_manage_image(bucket_id,name));
create policy tenant_images_insert on storage.objects for insert to authenticated
  with check (private.can_manage_image(bucket_id,name));
create policy tenant_images_update on storage.objects for update to authenticated
  using (private.can_manage_image(bucket_id,name)) with check (private.can_manage_image(bucket_id,name));
create policy tenant_images_delete on storage.objects for delete to authenticated
  using (private.can_manage_image(bucket_id,name));
commit;
