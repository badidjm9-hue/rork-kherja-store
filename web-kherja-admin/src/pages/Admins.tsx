import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Loader2, ShieldCheck, UserPlus, SlidersHorizontal, Save } from "lucide-react";
import { supabase, must, errorMessage, type AdminUser } from "@/lib/supabase";
import { useAuth } from "@/lib/auth";
import { useI18n } from "@/lib/i18n";
import { ROLE_CODES, roleLabel } from "@/lib/labels";
import { Avatar, EmptyState, ErrorBlock, LoadingBlock, PageHeader, Pill } from "@/components/kj";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";

const permissionArabic: Record<string, string> = {
  "overview.read": "عرض لوحة التحكم",
  "users.read": "عرض الركاب",
  "users.manage": "تعليق وإعادة تفعيل حسابات الركاب",
  "drivers.read": "عرض السائقين",
  "drivers.approve": "قبول أو رفض السائقين",
  "drivers.manage": "تعليق وإعادة تفعيل حسابات السائقين",
  "rides.read": "عرض الرحلات والعروض",
  "rides.manage": "إلغاء الرحلات",
  "finance.read": "عرض المعاملات والماليات",
  "finance.adjust": "إجراء التسويات والاستردادات",
  "pricing.read": "عرض الأسعار والعمولات",
  "pricing.manage": "تعديل ونشر الأسعار والعمولات",
  "admins.manage": "إدارة المسؤولين والموظفين",
  "audit.read": "عرض سجل التدقيق",
  "deliveries.read": "عرض طلبات التوصيل",
  "deliveries.manage": "إلغاء طلبات التوصيل",
  "vehicles.read": "عرض المركبات",
  "vehicles.manage": "تعليق وإعادة تفعيل المركبات",
  "notifications.read": "عرض الإشعارات المرسلة",
  "notifications.manage": "إرسال الإشعارات",
  "reports.read": "عرض التقارير",
  "settings.read": "عرض الإعدادات",
  "settings.manage": "تعديل الإعدادات",
  "support.read": "عرض الدعم وتنبيهات SOS",
  "support.manage": "معالجة تذاكر الدعم وتنبيهات SOS",
};

type PermissionRow = { code: string; description: string };
type IndividualPermission = { permission_code: string };

export default function Admins() {
  const { t, relative } = useI18n();
  const { admin } = useAuth();
  const qc = useQueryClient();
  const admins = useQuery({
    queryKey: ["admin-users"],
    queryFn: async () => must(await supabase.from("admin_users").select("*").order("created_at")) as AdminUser[],
  });
  const perms = useQuery({
    queryKey: ["admin-permissions"],
    queryFn: async () => must(await supabase.from("admin_permissions").select("code,description").order("code")) as PermissionRow[],
  });
  const [email,setEmail]=useState("");
  const [name,setName]=useState("");
  const [role,setRole]=useState("support_agent");
  const [busy,setBusy]=useState<string|null>(null);
  const [selectedUser,setSelectedUser]=useState<string|null>(null);
  const [customEnabled,setCustomEnabled]=useState(true);
  const [selectedPermissions,setSelectedPermissions]=useState<string[]>([]);
  const selectedAdmin=admins.data?.find(a=>a.user_id===selectedUser)??null;
  const individual=useQuery({
    queryKey:["admin-user-permissions",selectedUser],
    enabled:Boolean(selectedUser),
    queryFn:async()=>must(await supabase.from("admin_user_permissions").select("permission_code").eq("user_id",selectedUser!)) as IndividualPermission[],
  });
  useEffect(()=>{
    if(!selectedAdmin||!individual.data)return;
    setCustomEnabled(Boolean(selectedAdmin.custom_permissions_enabled));
    setSelectedPermissions(individual.data.map(x=>x.permission_code));
  },[selectedAdmin?.user_id,selectedAdmin?.custom_permissions_enabled,individual.data]);

  const setAdmin=async(key:string,args:{p_email:string;p_role:string;p_active?:boolean;p_display_name?:string},ok:string)=>{
    setBusy(key);
    try{must(await supabase.rpc("admin_set_admin",args));toast.success(ok);await qc.invalidateQueries({queryKey:["admin-users"]});if(key!=="new")await qc.invalidateQueries({queryKey:["admin-user-permissions",key]});return true;}
    catch(e){toast.error(errorMessage(e));return false;}finally{setBusy(null);}
  };
  const savePermissions=async()=>{
    if(!selectedUser)return;
    setBusy("permissions");
    try{
      must(await supabase.rpc("admin_set_user_permissions",{p_user_id:selectedUser,p_permission_codes:customEnabled?selectedPermissions:[],p_use_custom:customEnabled}));
      toast.success(t("Permissions enregistrées","تم حفظ الصلاحيات"));
      await Promise.all([qc.invalidateQueries({queryKey:["admin-users"]}),qc.invalidateQueries({queryKey:["admin-user-permissions",selectedUser]}),qc.invalidateQueries({queryKey:["audit"]})]);
    }catch(e){toast.error(errorMessage(e));}finally{setBusy(null);}
  };
  const createStaff=async(e:FormEvent)=>{
    e.preventDefault();
    const normalized=email.trim().toLowerCase();
    setBusy("new");
    try{
      const invited=must(await supabase.functions.invoke("admin-invite",{
        body:{email:normalized,display_name:name.trim(),role},
      })) as {user_id:string; invited:boolean};
      toast.success(invited.invited
        ? t("Invitation envoyée. Configurez ses permissions.","تم إرسال الدعوة. اضبط صلاحيات الموظف.")
        : t("Compte existant ajouté. Configurez ses permissions.","تمت إضافة الحساب الموجود. اضبط صلاحياته."));
      setEmail("");setName("");setSelectedUser(invited.user_id);setCustomEnabled(true);setSelectedPermissions([]);
      await Promise.all([qc.invalidateQueries({queryKey:["admin-users"]}),qc.invalidateQueries({queryKey:["admin-user-permissions",invited.user_id]})]);
    }catch(err){toast.error(errorMessage(err));}
    finally{setBusy(null);}
  };
  const selectedSet=useMemo(()=>new Set(selectedPermissions),[selectedPermissions]);
  const toggle=(code:string,checked:boolean)=>setSelectedPermissions(old=>checked?[...new Set([...old,code])]:old.filter(x=>x!==code));

  return <div className="space-y-6">
    <PageHeader title={t("Administrateurs et employés","المسؤولون والموظفون")} subtitle={t("Créez des accès de travail et choisissez précisément les permissions de chaque employé.","أضف حسابات العمل واختر بدقة صلاحيات كل موظف.")}/>
    <div className="grid gap-5 xl:grid-cols-[1fr_390px]">
      <section className="kj-card divide-y">
        <div className="flex items-center justify-between px-5 py-4"><h2 className="font-bold">{t("Équipe d'administration","فريق الإدارة")}</h2><Pill tone="blue">{admins.data?.length??0}</Pill></div>
        {admins.isLoading&&<LoadingBlock/>}{admins.error&&<ErrorBlock error={admins.error}/>}
        {admins.data?.length===0&&<EmptyState icon={ShieldCheck} title={t("Aucun administrateur","لا يوجد مسؤولون")}/>}
        {admins.data?.map(a=>{
          const self=a.user_id===admin?.user_id;const isSuper=a.role_code==="super_admin";
          return <div key={a.user_id} className="flex flex-wrap items-center gap-3 px-5 py-4">
            <Avatar name={a.display_name}/>
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{a.display_name} {self&&<span className="text-xs text-muted-foreground">({t("vous","أنت")})</span>}</p>
              <p className="truncate text-sm text-muted-foreground">{a.email??"—"}</p>
              <p className="text-xs text-muted-foreground">{roleLabel(t,a.role_code)} · {a.custom_permissions_enabled?t("Permissions personnalisées","صلاحيات مخصصة"):t("Rôle standard","صلاحيات الدور")}</p>
              <p className="text-xs text-muted-foreground">{t("Dernière activité","آخر نشاط")}: {a.last_seen_at?relative(a.last_seen_at):t("jamais","أبدًا")}</p>
            </div>
            <select disabled={self||busy===a.user_id||!a.email||isSuper} value={a.role_code}
              onChange={e=>void setAdmin(a.user_id,{p_email:a.email!,p_role:e.target.value,p_active:a.active,p_display_name:a.display_name},t("Rôle mis à jour","تم تحديث الدور"))}
              className="h-9 rounded-xl border bg-card px-3 text-sm font-semibold">
              {ROLE_CODES.filter(r=>r!=="super_admin").map(r=><option key={r} value={r}>{roleLabel(t,r)}</option>)}
            </select>
            <div className="flex items-center gap-2"><Pill tone={a.active?"green":"gray"}>{a.active?t("Actif","نشط"):t("Désactivé","معطل")}</Pill>
              <Switch disabled={self||isSuper||!a.email||busy===a.user_id} checked={a.active}
                onCheckedChange={x=>void setAdmin(a.user_id,{p_email:a.email!,p_role:a.role_code,p_active:x,p_display_name:a.display_name},x?t("Accès réactivé","تم تفعيل الوصول"):t("Accès désactivé","تم تعطيل الوصول"))}/></div>
            {!isSuper&&<Button size="sm" variant={selectedUser===a.user_id?"default":"outline"} onClick={()=>setSelectedUser(a.user_id)}><SlidersHorizontal className="h-4 w-4"/>{t("Permissions","الصلاحيات")}</Button>}
          </div>;
        })}
      </section>
      <div className="space-y-5">
        <form className="kj-card space-y-4 p-5" onSubmit={createStaff}>
          <div className="flex items-center gap-3"><span className="grid h-9 w-9 place-items-center rounded-xl bg-accent text-primary"><UserPlus className="h-[18px] w-[18px]"/></span>
            <div><p className="font-bold">{t("Ajouter un employé","إضافة موظف")}</p><p className="text-xs text-muted-foreground">{t("Une invitation sera envoyée à cette adresse.","سيتم إرسال دعوة إلى هذا البريد الإلكتروني.")}</p></div></div>
          <div className="space-y-1.5"><Label>{t("Email","البريد الإلكتروني")}</Label><Input type="email" required value={email} onChange={e=>setEmail(e.target.value)} className="h-10 rounded-xl"/></div>
          <div className="space-y-1.5"><Label>{t("Nom affiché","الاسم الظاهر")}</Label><Input value={name} onChange={e=>setName(e.target.value)} className="h-10 rounded-xl"/></div>
          <div className="space-y-1.5"><Label>{t("Rôle de base","الدور الأساسي")}</Label><select value={role} onChange={e=>setRole(e.target.value)} className="h-10 w-full rounded-xl border bg-card px-3 text-sm">
            {ROLE_CODES.filter(r=>r!=="super_admin").map(r=><option key={r} value={r}>{roleLabel(t,r)}</option>)}</select></div>
          <Button type="submit" className="h-11 w-full font-bold" disabled={busy==="new"||!email.trim()}>{busy==="new"&&<Loader2 className="h-4 w-4 animate-spin"/>}{t("Inviter l'employé","إرسال دعوة الموظف")}</Button>
        </form>
        {selectedAdmin&&<section className="kj-card space-y-4 p-5">
          <div><p className="font-bold">{t("Permissions de","صلاحيات")} {selectedAdmin.display_name}</p><p className="text-xs text-muted-foreground">{t("Désactive le mode personnalisé pour revenir aux permissions du rôle.","عطّل الصلاحيات المخصصة للعودة إلى صلاحيات الدور.")}</p></div>
          {individual.isLoading||perms.isLoading?<LoadingBlock/>:individual.error||perms.error?<ErrorBlock error={individual.error||perms.error}/>:<>
            <label className="flex items-center justify-between rounded-xl bg-muted/50 p-3 text-sm font-semibold"><span>{t("Utiliser des permissions personnalisées","استخدام صلاحيات مخصصة")}</span><Switch checked={customEnabled} onCheckedChange={setCustomEnabled}/></label>
            <div className="flex justify-end gap-2">
              <Button type="button" size="sm" variant="ghost" disabled={!customEnabled} onClick={()=>setSelectedPermissions(perms.data?.map(p=>p.code)??[])}>{t("Tout sélectionner","تحديد الكل")}</Button>
              <Button type="button" size="sm" variant="ghost" disabled={!customEnabled} onClick={()=>setSelectedPermissions([])}>{t("Tout effacer","مسح الكل")}</Button>
            </div>
            <div className={customEnabled?"space-y-2":"pointer-events-none space-y-2 opacity-40"}>
              {perms.data?.map(p=><label key={p.code} className="flex items-start gap-3 rounded-lg border p-2.5 text-sm">
                <input type="checkbox" className="mt-1 h-4 w-4 accent-primary" checked={selectedSet.has(p.code)} disabled={p.code==="admins.manage"&&admin?.role!=="super_admin"} onChange={e=>toggle(p.code,e.target.checked)}/>
                <span className="min-w-0"><span className="block font-semibold">{p.code}</span><span className="block text-xs text-muted-foreground">{t(p.description,permissionArabic[p.code]??p.description)}</span></span>
              </label>)}
            </div>
            <div className="flex items-center justify-between gap-3 border-t pt-3"><span className="text-xs text-muted-foreground">{customEnabled?selectedPermissions.length+" "+t("permissions sélectionnées","صلاحية محددة"):t("Permissions du rôle","صلاحيات الدور")}</span>
              <Button disabled={busy==="permissions"||individual.isLoading} onClick={()=>void savePermissions()}>{busy==="permissions"?<Loader2 className="h-4 w-4 animate-spin"/>:<Save className="h-4 w-4"/>}{t("Enregistrer","حفظ")}</Button></div>
          </>}
        </section>}
        <div className="kj-card p-4 text-xs leading-relaxed text-muted-foreground">{t("La sécurité est vérifiée par PostgreSQL. Les permissions personnalisées remplacent les permissions du rôle. Le super administrateur conserve toujours tous les accès.","تتحقق قاعدة البيانات من الصلاحيات. الصلاحيات المخصصة تستبدل صلاحيات الدور. المدير العام يحتفظ دائماً بكامل الوصول.")}</div>
      </div>
    </div>
  </div>;
}
