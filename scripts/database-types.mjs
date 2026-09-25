// Geração local pelo catálogo PostgreSQL, sem credenciais ou duplicação manual do schema.
export async function generateTypes(db) {
  const { rows: enums } = await db.query(`select t.typname, array_agg(e.enumlabel order by e.enumsortorder) labels
    from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace
    where n.nspname='public' group by t.typname order by t.typname`)
  const { rows: columns } = await db.query(`select table_name,column_name,is_nullable,column_default,data_type,udt_name
    from information_schema.columns where table_schema='public' order by table_name,ordinal_position`)
  const { rows: fks } = await db.query(`select c.conname, r.relname as source, f.relname as target,
    exists(select 1 from pg_constraint u where u.conrelid=c.conrelid and u.contype in ('p','u')
      and u.conkey @> c.conkey and u.conkey <@ c.conkey) as one_to_one,
    array(select a.attname from unnest(c.conkey) with ordinality k(num,ord)
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num order by k.ord) as columns,
    array(select a.attname from unnest(c.confkey) with ordinality k(num,ord)
      join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.num order by k.ord) as referenced_columns
    from pg_constraint c join pg_class r on r.oid=c.conrelid join pg_class f on f.oid=c.confrelid
    join pg_namespace n on n.oid=r.relnamespace join pg_namespace nf on nf.oid=f.relnamespace
    where c.contype='f' and n.nspname='public' and nf.nspname='public' order by c.conname`)
  const enumNames = new Set(enums.map(e=>e.typname))
  const { rows: functions } = await db.query(`select p.proname,p.proargnames,p.pronargdefaults,t.typname as result_type,
    array(select typname from unnest(p.proargtypes::oid[]) with ordinality a(id,ord)
      join pg_type t on t.oid=a.id order by a.ord) as arg_types
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_type t on t.oid=p.prorettype
    where n.nspname='public' order by p.proname`)
  function type(name) {
    if (name.startsWith('_')) return `(${type(name.slice(1))})[]`
    if (enumNames.has(name)) return `Database['public']['Enums']['${name}']`
    if (['int2','int4','int8','numeric','float4','float8'].includes(name)) return 'number'
    if (name==='bool') return 'boolean'
    if (['json','jsonb'].includes(name)) return 'Json'
    if (name==='void') return 'undefined'
    return 'string'
  }
  const tables = [...new Set(columns.map(c=>c.table_name))].map(name=>{
    const cols = columns.filter(c=>c.table_name===name)
    const fields = (mode) => cols.map(c=>`          ${c.column_name}${mode==='Update' ||
      (mode==='Insert' && (c.column_default!==null || c.is_nullable==='YES')) ? '?' : ''}: ${type(c.udt_name)}${c.is_nullable==='YES'?' | null':''}`).join('\n')
    const relationships = fks.filter(f=>f.source===name).map(f=>`          { foreignKeyName: ${JSON.stringify(f.conname)}; columns: ${JSON.stringify(f.columns)}; isOneToOne: ${f.one_to_one}; referencedRelation: ${JSON.stringify(f.target)}; referencedColumns: ${JSON.stringify(f.referenced_columns)} }`).join(',\n')
    return `      ${name}: {\n${['Row','Insert','Update'].map(mode=>`        ${mode}: {\n${fields(mode)}\n        }`).join('\n')}\n        Relationships: [\n${relationships}\n        ]\n      }`
  }).join('\n')
  const functionTypes = functions.map(f=>`      ${f.proname}: { Args: { ${f.arg_types.map((t,i)=>`${f.proargnames[i]}${i>=f.arg_types.length-f.pronargdefaults?'?':''}: ${type(t)}`).join('; ') || '[key: string]: never'} }; Returns: ${type(f.result_type)} }`).join('\n')
  return `// GERADO por npm run db:types a partir das migrations. Não editar manualmente.\nexport type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]\n\nexport type Database = {\n  public: {\n    Tables: {\n${tables}\n    }\n    Views: { [_ in never]: never }\n    Functions: {\n${functionTypes}\n    }\n    Enums: {\n${enums.map(e=>`      ${e.typname}: ${e.labels.map(l=>JSON.stringify(l)).join(' | ')}`).join('\n')}\n    }\n    CompositeTypes: { [_ in never]: never }\n  }\n}\n`
}
