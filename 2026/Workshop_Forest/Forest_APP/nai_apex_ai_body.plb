create or replace package body nai_apex_ai as
  c_meta constant varchar2(30) := 'NAI_AI_META';
  c_history constant varchar2(30) := 'NAI_AI_HISTORY';
  c_map constant varchar2(30) := 'NAI_AI_MAP';
  c_max_rows constant pls_integer := 200;
  c_max_features constant pls_integer := 600;
  g_skipped pls_integer := 0;

  procedure reset_collection(p_name varchar2) is
  begin
    apex_collection.create_or_truncate_collection(p_collection_name=>p_name);
  end;

  procedure init is
  begin
    if apex_application.g_flow_id is null or apex_application.g_instance is null
       or apex_application.g_user is null
       or upper(apex_application.g_user) in ('NOBODY','APEX_PUBLIC_USER') then
      raise_application_error(-20001,'Sign in to the APEX application first.');
    end if;
    for r in (select c_meta n from dual union all select c_history from dual
              union all select c_map from dual) loop
      if not apex_collection.collection_exists(r.n) then
        apex_collection.create_collection(r.n);
      end if;
    end loop;
  end;

  procedure clean_session is
  begin
    dbms_cloud_ai.clear_conversation_id;
    dbms_cloud_ai_agent.clear_team;
  end;

  function params(p_id varchar2) return clob is
    l_obj json_object_t := json_object_t();
  begin
    l_obj.put('conversation_id',p_id);
    return l_obj.to_clob();
  end;

  function invoke_ai(p_prompt clob, p_id varchar2,
                     p_profile varchar2 default null,
                     p_action varchar2 default null,
                     p_team varchar2 default null) return clob is
    l_numeric varchar2(10);
    l_changed boolean := false;
    l_result clob;
    procedure restore_format is
    begin
      if l_changed then
        dbms_session.set_nls('NLS_NUMERIC_CHARACTERS',
          ''''||replace(l_numeric,'''','''''')||'''');
        l_changed := false;
      end if;
    end;
  begin
    -- The installed cloud AI package converts numeric profile attributes using
    -- the caller's NLS format. APEX's Norwegian decimal comma makes it fail.
    select value into l_numeric from nls_session_parameters
      where parameter='NLS_NUMERIC_CHARACTERS';
    if l_numeric <> '.,' then
      dbms_session.set_nls('NLS_NUMERIC_CHARACTERS','''.,''');
      l_changed := true;
    end if;
    if p_team is not null then
      l_result := dbms_cloud_ai_agent.run_team(team_name=>p_team,
        user_prompt=>p_prompt,params=>params(p_id));
    else
      l_result := dbms_cloud_ai.generate(prompt=>p_prompt,
        profile_name=>p_profile,action=>p_action,params=>params(p_id));
    end if;
    restore_format;
    return l_result;
  exception when others then
    restore_format;
    raise;
  end;

  procedure add_geometry(p_geom mdsys.sdo_geometry, p_label varchar2) is
    l_geom mdsys.sdo_geometry := p_geom;
    l_kind varchar2(20);
    l_json clob;
  begin
    if l_geom is null then return; end if;
    if apex_collection.collection_member_count(c_map) >= c_max_features then
      g_skipped := g_skipped+1; return;
    end if;
    -- Never assume an unknown coordinate system is WGS84.
    if l_geom.sdo_srid is null then
      g_skipped := g_skipped+1; return;
    end if;
    if l_geom.sdo_srid <> 4326 then
      l_geom := mdsys.sdo_cs.transform(l_geom,4326);
    end if;
    -- TO_GEOJSON does not support all 3D/LRS/curve geometries. Report skips.
    l_kind := case mod(l_geom.sdo_gtype,1000)
      when 1 then 'POINT' when 5 then 'POINT'
      when 2 then 'LINE' when 6 then 'LINE'
      when 3 then 'POLYGON' when 7 then 'POLYGON' 
    end;
    if l_kind is null then g_skipped := g_skipped+1; return; end if;
    l_json := mdsys.sdo_util.to_geojson(l_geom);
    apex_collection.add_member(p_collection_name=>c_map,
      p_c001=>substr(p_label,1,1000),p_c002=>l_kind,p_clob001=>l_json);
  exception when others then
    -- A single geometry must not discard an otherwise successful AI answer.
    g_skipped := g_skipped+1;
    apex_debug.error('NAI geometry: %s',sqlerrm);
  end;

  function normalize_sql(p_sql clob) return varchar2 is
    l_sql varchar2(32767);
  begin
    if p_sql is null or dbms_lob.getlength(p_sql)>30000 then
      raise_application_error(-20002,'AI did not return SQL, or the SQL exceeds 30,000 characters.');
    end if;
    l_sql := trim(dbms_lob.substr(p_sql,30000,1));
    if substr(l_sql,1,3)='```' then
      l_sql := regexp_replace(l_sql,'^```[a-zA-Z]*[[:space:]]*','');
      l_sql := regexp_replace(l_sql,'[[:space:]]*```[[:space:]]*$','');
    end if;
    l_sql := regexp_replace(trim(l_sql),';[[:space:]]*$','');
    -- Conservative query gate; not a sandbox for hostile database users.
    -- Wrapping the statement below also prevents a WITH PL/SQL declaration.
    if not regexp_like(l_sql,'^(SELECT|WITH)[[:space:]]','i')
       or instr(l_sql,';')>0 or instr(l_sql,'--')>0 or instr(l_sql,'/*')>0
       or instr(l_sql,'@')>0
       or regexp_like(l_sql,'(^|[^A-Z0-9_$#])(INSERT|UPDATE|DELETE|MERGE|ALTER|DROP|CREATE|GRANT|REVOKE|EXECUTE|BEGIN|DECLARE|COMMIT|ROLLBACK|DBMS_[A-Z0-9_]+|UTL_[A-Z0-9_]+|APEX_[A-Z0-9_]+)([^A-Z0-9_$#]|$)','i') then
      raise_application_error(-20003,'The SQL could not be executed as a simple read-only query. See the generated SQL.');
    end if;
    return l_sql;
  end;

  function run_query(p_sql clob) return clob is
    l_ctx apex_exec.t_context;
    l_open boolean := false;
    l_column apex_exec.t_column;
    l_cols apex_exec.t_columns;
    l_html clob;
    l_value varchar2(32767);
    l_geom mdsys.sdo_geometry;
    l_rows pls_integer := 0;
    l_sql varchar2(32767);
    l_stand_id number;
    l_row_has_geometry boolean;
    l_forest_query boolean;
    procedure put(p_text varchar2) is
    begin l_html := l_html || p_text; end;
  begin
    l_sql := normalize_sql(p_sql);
    l_forest_query := regexp_like(l_sql,'(^|[^A-Z0-9_$#])NF_STAND(_V)?([^A-Z0-9_$#]|$)','i');
    l_ctx := apex_exec.open_query_context(
      p_location=>apex_exec.c_location_local_db,
      p_sql_query=>'select * from ('||l_sql||') NAI_Q',
      p_auto_bind_items=>false,p_max_rows=>c_max_rows+1);
    l_open := true;
    put('<div class="nai-table-wrap"><table class="nai-table"><thead><tr>');
    for i in 1..apex_exec.get_column_count(l_ctx) loop
      l_cols(i) := apex_exec.get_column(l_ctx,i);
      put('<th scope="col">'||apex_escape.html(l_cols(i).name)||'</th>');
    end loop;
    put('</tr></thead><tbody>');
    while apex_exec.next_row(l_ctx) loop
      l_rows := l_rows+1;
      exit when l_rows>c_max_rows;
      l_stand_id := null;
      l_row_has_geometry := false;
      put('<tr>');
      for i in 1..l_cols.count loop
        l_value := null;
        case l_cols(i).data_type
          when apex_exec.c_data_type_sdo_geometry then
            l_geom := apex_exec.get_sdo_geometry(l_ctx,i);
            if l_geom is not null then
              add_geometry(l_geom,l_cols(i).name||' · row '||l_rows);
              l_row_has_geometry := true;
              l_value := 'Geometry (SRID '||nvl(to_char(l_geom.sdo_srid),'unknown')||')';
            end if;
          when apex_exec.c_data_type_number then
            l_value := to_char(apex_exec.get_number(l_ctx,i));
            if upper(l_cols(i).name)='STAND_ID' then
              l_stand_id := apex_exec.get_number(l_ctx,i);
            end if;
          when apex_exec.c_data_type_date then
            l_value := to_char(apex_exec.get_date(l_ctx,i),'YYYY-MM-DD HH24:MI:SS');
          when apex_exec.c_data_type_timestamp then
            l_value := to_char(apex_exec.get_timestamp(l_ctx,i),'YYYY-MM-DD HH24:MI:SS.FF3');
          when apex_exec.c_data_type_timestamp_tz then
            l_value := to_char(apex_exec.get_timestamp_tz(l_ctx,i),'YYYY-MM-DD HH24:MI:SS TZH:TZM');
          when apex_exec.c_data_type_timestamp_ltz then
            l_value := to_char(apex_exec.get_timestamp_ltz(l_ctx,i),'YYYY-MM-DD HH24:MI:SS');
          when apex_exec.c_data_type_clob then
            l_value := dbms_lob.substr(apex_exec.get_clob(l_ctx,i),2000,1);
          when apex_exec.c_data_type_varchar2 then
            l_value := substr(apex_exec.get_varchar2(l_ctx,i),1,2000);
          else l_value := '[data type '||apex_exec.get_data_type(l_cols(i).data_type)||']';
        end case;
        put('<td>'||apex_escape.html(l_value)||'</td>');
      end loop;
      -- The installed AI profile uses NF_STAND_V, which omits GEOM.
      -- Resolve that view's returned primary key against its base table.
      if l_forest_query and not l_row_has_geometry and l_stand_id is not null then
        for r in (select b.geom,b.name from nf_stand b where b.stand_id=l_stand_id) loop
          add_geometry(r.geom,'Forest stand '||l_stand_id||' · '||r.name);
        end loop;
      end if;
      put('</tr>');
    end loop;
    apex_exec.close(l_ctx); l_open := false;
    put('</tbody></table></div><p>'||least(l_rows,c_max_rows)||' rows displayed.');
    if l_rows>c_max_rows then put(' The result is limited to 200 rows.'); end if;
    put('</p>');
    if l_forest_query then
      put('<p class="nai-note">For forest rows with STAND_ID and no geometry column, the full forest stand geometry is retrieved from NF_STAND.</p>');
    end if;
    if apex_collection.collection_member_count(c_map)=0 then
      put('<p class="nai-note">No mappable geometry in the result. Request an SDO_GEOMETRY column, or STAND_ID for forest data.</p>');
    end if;
    return l_html;
  exception when others then
    if l_open then apex_exec.close(l_ctx); end if;
    raise;
  end;

  function json_response(p_response clob) return json_object_t is
    l_text clob := trim(p_response);
  begin
    if dbms_lob.substr(l_text,3,1)='```' then
      l_text := regexp_replace(l_text,'^```[a-zA-Z]*[[:space:]]*','');
      l_text := regexp_replace(l_text,'[[:space:]]*```[[:space:]]*$','');
    end if;
    return json_object_t.parse(l_text);
  exception when others then return null;
  end;

  procedure agent_map(p_obj json_object_t) is
    l_json clob;
  begin
    if p_obj is null or not p_obj.has('stand_ids') then return; end if;
    l_json := p_obj.to_clob();
    -- Only IDs in a structured response are used; never numbers in free text.
    -- Coordinates always come from NF_STAND, never from model-generated JSON.
    for r in (
      select b.stand_id,b.name,b.geom
      from nf_stand b
      where b.stand_id in (
        select j.id from json_table(l_json,'$.stand_ids[*]'
          columns (id number path '$' null on error)) j)
      order by b.stand_id fetch first 200 rows only
    ) loop
      add_geometry(r.geom,'Forest stand '||r.stand_id||' · '||r.name);
    end loop;
  end;

  function agent_prompt(p_question varchar2) return clob is
    l_prompt clob;
    l_obj json_object_t;
  begin
    -- Some existing teams do not inject prior task responses into their LLM
    -- prompt even when RUN_TEAM receives the same conversation_id.
    -- Supply recent turns from this authenticated APEX session as context too.
    for r in (select clob001 from apex_collections
              where collection_name=c_history
                and seq_id>(select nvl(max(seq_id),0)-5 from apex_collections
                            where collection_name=c_history)
              order by seq_id) loop
      l_obj := json_object_t.parse(r.clob001);
      l_prompt := l_prompt || chr(10)||'Previous question: '||
        dbms_lob.substr(l_obj.get_clob('prompt'),2000,1)||chr(10)||
        'Previous response: '||dbms_lob.substr(l_obj.get_clob('answer'),2000,1)||chr(10);
    end loop;
    if l_prompt is not null then
      l_prompt := 'Previous conversation, for context only. Use tools to verify new data requests.'||
        chr(10)||l_prompt||chr(10)||'Current question: ';
    end if;
    return l_prompt || p_question;
  end;

  function history_html return clob is
    l_html clob;
    l_obj json_object_t;
    procedure put(p_text varchar2) is
    begin l_html := l_html || p_text; end;
  begin
    for r in (select c001,clob001 from apex_collections
              where collection_name=c_history order by seq_id) loop
      l_obj := json_object_t.parse(r.clob001);
      put('<article class="nai-turn"><div class="nai-question"><span>You</span><pre>');
      l_html := l_html || apex_escape.html_clob(l_obj.get_clob('prompt'));
      put('</pre></div><div class="nai-answer"><span>'||apex_escape.html(r.c001)||'</span><pre>');
      l_html := l_html || apex_escape.html_clob(l_obj.get_clob('answer'));
      put('</pre>');
      if l_obj.has('sql') then
        put('<details><summary>Generated SQL</summary><pre>');
        l_html := l_html || apex_escape.html_clob(l_obj.get_clob('sql'));
        put('</pre></details>');
      end if;
      if l_obj.has('table_html') then
        -- Produced exclusively by run_query; all database values are escaped.
        l_html := l_html || l_obj.get_clob('table_html');
      end if;
      if l_obj.has('note') then
        put('<p class="nai-note">'||apex_escape.html(l_obj.get_string('note'))||'</p>');
      end if;
      put('</div></article>');
    end loop;
    if l_html is null then
      l_html := '<p class="nai-empty">Ask a question to start a conversation.</p>';
    end if;
    return l_html;
  end;

  procedure ajax(p_operation varchar2, p_mode varchar2, p_profile varchar2,
                 p_team varchar2, p_action varchar2, p_prompt varchar2) is
    l_id varchar2(36);
    l_old_key varchar2(1000);
    l_key varchar2(1000);
    l_count number;
    l_response clob;
    l_sql clob;
    l_table clob;
    l_note varchar2(4000);
    l_label varchar2(200);
    l_obj json_object_t;
    l_payload json_object_t := json_object_t();
    l_attrs json_object_t := json_object_t();
    l_prompt clob;
  begin
    init;
    if p_operation not in ('INIT','NEW','SEND') or p_operation is null then
      raise_application_error(-20004,'Unknown operation.');
    end if;
    if p_operation='NEW' then
      reset_collection(c_meta); reset_collection(c_history); reset_collection(c_map);
    end if;
    if p_operation='SEND' then
      if trim(p_prompt) is null or lengthb(p_prompt)>20000 then
        raise_application_error(-20005,'Enter a question of no more than 20,000 bytes.');
      end if;
      if p_mode='SELECT_AI' then
        select count(*) into l_count from user_cloud_ai_profiles
          where profile_name=p_profile and status='ENABLED';
        if l_count<>1 then raise_application_error(-20006,'Select an enabled AI profile.'); end if;
        if p_action not in ('narrate','chat','sql_map') or p_action is null then
          raise_application_error(-20007,'Select a valid Select AI action.');
        end if;
        l_key := p_mode||':'||p_profile||':'||p_action;
        l_label := 'Select AI · '||p_profile;
      elsif p_mode='AGENT' then
        select count(*) into l_count from user_ai_agent_teams
          where agent_team_name=p_team and status='ENABLED';
        if l_count<>1 then raise_application_error(-20008,'Select an enabled agent team.'); end if;
        l_key := p_mode||':'||p_team;
        l_label := 'Agent · '||p_team;
      else raise_application_error(-20009,'Choose Select AI or Agent team.');
      end if;
      begin
        select c001,c002 into l_id,l_old_key from apex_collections
          where collection_name=c_meta and seq_id=1;
      exception when no_data_found then null;
      end;
      if l_id is null or l_old_key<>l_key then
        clean_session;
        l_attrs.put('title','NIBIO AI');
        l_attrs.put('retention_days',7);
        l_attrs.put('conversation_length',20);
        l_id := dbms_cloud_ai.create_conversation(attributes=>l_attrs.to_clob());
        reset_collection(c_meta); reset_collection(c_history); reset_collection(c_map);
        apex_collection.add_member(p_collection_name=>c_meta,p_c001=>l_id,p_c002=>l_key);
      end if;
      clean_session;
      reset_collection(c_map); g_skipped := 0;
      if p_mode='AGENT' then
        l_prompt := agent_prompt(p_prompt);
        if p_team='NF_FOREST_TEAM' then
          l_prompt := l_prompt || chr(10)||chr(10)||
            'Format for APEX display: Return one JSON object without Markdown, with the fields '||
            '"answer" (the response in English) and "stand_ids" (a list of stand_id values from the tool result). '||
            'Use only IDs from results for this specific question. '||
            'Do not return coordinates. If you have no forest stand IDs, use an empty list. '||
            'Example format: {"answer":"...","stand_ids":[1,4]}. '||
            'Use appropriate tools and include stand_id in the SQL result.';
        end if;
        l_response := invoke_ai(p_prompt=>l_prompt,p_id=>l_id,p_team=>p_team);
        l_obj := json_response(l_response);
        if p_team='NF_FOREST_TEAM' then
          begin
            agent_map(l_obj);
          exception when others then
            l_note := 'The team response was received, but the map data could not be read: '||substr(sqlerrm,1,1000);
          end;
        end if;
        if l_obj is not null then
          if l_obj.has('answer') then l_response := l_obj.get_clob('answer'); end if;
        end if;
        if apex_collection.collection_member_count(c_map)=0 then
          l_note := nvl(l_note,'The response contains no mappable forest stand IDs. '||
            'Map integration for agent teams uses NF_STAND. Other teams need a corresponding integration.');
        end if;
      elsif p_action='sql_map' then
        l_sql := invoke_ai(p_prompt=>p_prompt,p_id=>l_id,
          p_profile=>p_profile,p_action=>'showsql');
        begin
          l_table := run_query(l_sql);
          l_response := 'Results from the database. The map displays geometries associated with these rows.';
        exception when others then
          reset_collection(c_map);
          l_response := 'SQL was generated but could not be executed.';
          l_note := substr(sqlerrm,1,3500);
        end;
      else
        l_response := invoke_ai(p_prompt=>p_prompt,p_id=>l_id,
          p_profile=>p_profile,p_action=>p_action);
        l_note := 'Select "SQL results and map" to retrieve rows and display SDO_GEOMETRY on the map.';
      end if;
      clean_session;
      if g_skipped>0 then
        l_note := substr(l_note||' '||g_skipped||
          ' geometries were omitted (unknown SRID, unsupported type, conversion error or map limit).',1,4000);
      end if;
      l_payload.put('answer',l_response);
      l_payload.put('prompt',p_prompt);
      if l_sql is not null then l_payload.put('sql',l_sql); end if;
      if l_table is not null then l_payload.put('table_html',l_table); end if;
      if l_note is not null then l_payload.put('note',l_note); end if;
      apex_collection.add_member(p_collection_name=>c_history,
        p_c001=>l_label,p_clob001=>l_payload.to_clob());
    end if;
    begin
      select c001 into l_id from apex_collections where collection_name=c_meta and seq_id=1;
    exception when no_data_found then l_id := null;
    end;
    apex_json.open_object;
    apex_json.write('ok',true);
    apex_json.write('conversation_id',l_id);
    apex_json.write('history_html',history_html);
    apex_json.write('map_count',apex_collection.collection_member_count(c_map));
    apex_json.close_object;
  exception when others then
    begin clean_session; exception when others then null; end;
    apex_debug.error('NAI request: %s %s',sqlerrm,dbms_utility.format_error_backtrace);
    apex_json.open_object;
    apex_json.write('ok',false);
    -- "error" is reserved by apex.server.process and bypasses success handlers.
    apex_json.write('message',substr(sqlerrm,1,3500));
    apex_json.close_object;
  end;
end nai_apex_ai;
/