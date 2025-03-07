require 'spec_helper'

describe PgQuery do
  def parse_expr(expr)
    query = described_class.parse("SELECT " + expr + " FROM x")
    expect(query.tree).not_to be_nil
    expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
    expect(expr.node).to eq :a_expr
    expr.a_expr
  end

  it "parses a normalized query" do
    query = described_class.parse("SELECT $1 FROM x")
    expect(query.tree.stmts.first).to eq(
      PgQuery::RawStmt.new(
        stmt: PgQuery::Node.from(
          PgQuery::SelectStmt.new(
            target_list: [
              PgQuery::Node.from(
                PgQuery::ResTarget.new(
                  val: PgQuery::Node.from(
                    PgQuery::ParamRef.new(number: 1, location: 7)
                  ),
                  location: 7
                )
              )
            ],
            from_clause: [
              PgQuery::Node.from(PgQuery::RangeVar.new(relname: "x", inh: true, relpersistence: "p", location: 15))
            ],
            limit_option: :LIMIT_OPTION_DEFAULT,
            op: :SETOP_NONE
          )
        )
      )
    )
  end

  it 'keep locations correct' do
    query = described_class.parse("SELECT $1, 123")
    targetlist = query.tree.stmts.first.stmt.select_stmt.target_list
    expect(targetlist[0].res_target.location).to eq 7
    expect(targetlist[1].res_target.location).to eq 11
  end

  # This is a pg_query patch to support param refs in more places
  context 'additional param ref support' do
    it "parses INTERVAL $1" do
      query = described_class.parse("SELECT INTERVAL $1")
      targetlist = query.tree.stmts.first.stmt.select_stmt.target_list
      expect(targetlist[0].res_target.val).to eq(
        PgQuery::Node.from(
          PgQuery::TypeCast.new(
            arg: PgQuery::Node.from(
              PgQuery::ParamRef.new(number: 1, location: 16)
            ),
            type_name: PgQuery::TypeName.new(
              names: [
                PgQuery::Node.from_string("pg_catalog"),
                PgQuery::Node.from_string("interval")
              ],
              typemod: -1,
              location: 7
            ),
            location: -1
          )
        )
      )
    end

    it "parses INTERVAL $1 hour" do
      query = described_class.parse("SELECT INTERVAL $1 hour")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::TypeCast.new(
            arg: PgQuery::Node.from(
              PgQuery::ParamRef.new(number: 1, location: 16)
            ),
            type_name: PgQuery::TypeName.new(
              names: [
                PgQuery::Node.from_string("pg_catalog"),
                PgQuery::Node.from_string("interval")
              ],
              typmods: [
                PgQuery::Node.from(
                  PgQuery::A_Const.new(
                    val: PgQuery::Node.from_integer(1024),
                    location: 19
                  )
                )
              ],
              typemod: -1,
              location: 7
            ),
            location: -1
          )
        )
      )
    end

    # Note how Postgres does not replace the integer value here
    it "parses INTERVAL (2) $2" do
      query = described_class.parse("SELECT INTERVAL (2) $2")
      expect(query.tree).not_to be_nil
    end

    # Note how Postgres does not replace the integer value here
    it "parses cast($1 as varchar(2))" do
      query = described_class.parse("SELECT cast($1 as varchar(2))")
      expect(query.tree).not_to be_nil
    end

    it "parses substituted pseudo keywords in extract()" do
      query = described_class.parse("SELECT extract($1 from NOW())")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::FuncCall.new(
            funcname: [PgQuery::Node.from_string('pg_catalog'), PgQuery::Node.from_string('date_part')],
            args: [
              PgQuery::Node.from(PgQuery::ParamRef.new(number: 1, location: 15)),
              PgQuery::Node.from(
                PgQuery::FuncCall.new(
                  funcname: [PgQuery::Node.from_string('now')],
                  location: 23
                )
              )
            ],
            location: 7
          )
        )
      )
    end

    it "parses SET x = $1" do
      query = described_class.parse("SET statement_timeout = $1")
      expect(query.tree).not_to be_nil
    end

    it "parses SET x=$1" do
      query = described_class.parse("SET statement_timeout=$1")
      expect(query.tree).not_to be_nil
    end

    it "parses SET TIME ZONE $1" do
      query = described_class.parse("SET TIME ZONE $1")
      expect(query.tree).not_to be_nil
    end

    it "parses SET SCHEMA $1" do
      query = described_class.parse("SET SCHEMA $1")
      expect(query.tree).not_to be_nil
    end

    it "parses SET ROLE $1" do
      query = described_class.parse("SET ROLE $1")
      expect(query.tree).not_to be_nil
    end

    it "parses SET SESSION AUTHORIZATION $1" do
      query = described_class.parse("SET SESSION AUTHORIZATION $1")
      expect(query.tree).not_to be_nil
    end
  end

  # This syntax can be removed once Postgres 9.6 is EOL (since pg_stat_statements starting Postgres 10 uses $ param refs)
  context 'old style ? replacement handling' do
    it "parses a normalized query" do
      query = described_class.parse("SELECT ? FROM x")
      expect(query.tree.stmts.first).to eq(
        PgQuery::RawStmt.new(
          stmt: PgQuery::Node.from(
            PgQuery::SelectStmt.new(
              target_list: [
                PgQuery::Node.from(
                  PgQuery::ResTarget.new(
                    val: PgQuery::Node.from(
                      PgQuery::ParamRef.new(number: 0, location: 7)
                    ),
                    location: 7
                  )
                )
              ],
              from_clause: [
                PgQuery::Node.from(PgQuery::RangeVar.new(relname: "x", inh: true, relpersistence: "p", location: 14))
              ],
              limit_option: :LIMIT_OPTION_DEFAULT,
              op: :SETOP_NONE
            )
          )
        )
      )
    end

    it 'keep locations correct' do
      query = described_class.parse("SELECT ?, 123")
      targetlist = query.tree.stmts.first.stmt.select_stmt.target_list
      expect(targetlist[0].res_target.location).to eq 7
      expect(targetlist[1].res_target.location).to eq 10
    end

    it "parses INTERVAL ?" do
      query = described_class.parse("SELECT INTERVAL ?")
      targetlist = query.tree.stmts.first.stmt.select_stmt.target_list
      expect(targetlist[0].res_target.val).to eq(
        PgQuery::Node.from(
          PgQuery::TypeCast.new(
            arg: PgQuery::Node.from(
              PgQuery::ParamRef.new(number: 0, location: 16)
            ),
            type_name: PgQuery::TypeName.new(
              names: [
                PgQuery::Node.from_string("pg_catalog"),
                PgQuery::Node.from_string("interval")
              ],
              typemod: -1,
              location: 7
            ),
            location: -1
          )
        )
      )
    end

    it "parses INTERVAL ? hour" do
      query = described_class.parse("SELECT INTERVAL ? hour")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::TypeCast.new(
            arg: PgQuery::Node.from(
              PgQuery::ParamRef.new(number: 0, location: 16)
            ),
            type_name: PgQuery::TypeName.new(
              names: [
                PgQuery::Node.from_string("pg_catalog"),
                PgQuery::Node.from_string("interval")
              ],
              typmods: [
                PgQuery::Node.from(
                  PgQuery::A_Const.new(
                    val: PgQuery::Node.from_integer(0),
                    location: -1
                  )
                )
              ],
              typemod: -1,
              location: 7
            ),
            location: -1
          )
        )
      )
    end

    it "parses 'a ? b' in target list" do
      query = described_class.parse("SELECT a ? b")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::A_Expr.new(
            kind: :AEXPR_OP,
            name: [PgQuery::Node.from_string("?")],
            lexpr: PgQuery::Node.from(PgQuery::ColumnRef.new(fields: [PgQuery::Node.from_string('a')], location: 7)),
            rexpr: PgQuery::Node.from(PgQuery::ColumnRef.new(fields: [PgQuery::Node.from_string('b')], location: 11)),
            location: 9
          )
        )
      )
    end

    it "fails on '? 10' in target list" do
      # IMPORTANT: This is a difference of our patched parser from the main PostgreSQL parser
      #
      # This should be parsed as a left-unary operator, but we can't
      # support that due to keyword/function duality (e.g. JOIN)
      expect { described_class.parse("SELECT ? 10") }.to raise_error do |error|
        expect(error).to be_a(described_class::ParseError)
        expect(error.message).to eq "syntax error at or near \"10\" (scan.l:1230)"
      end
    end

    it "mis-parses on '? a' in target list" do
      # IMPORTANT: This is a difference of our patched parser from the main PostgreSQL parser
      #
      # This is mis-parsed as a target list name (should be a column reference),
      # but we can't avoid that.
      query = described_class.parse("SELECT ? a")
      restarget = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target
      expect(restarget).to eq(
        PgQuery::ResTarget.new(
          name: 'a',
          val: PgQuery::Node.from(PgQuery::ParamRef.new(number: 0, location: 7)),
          location: 7
        )
      )
    end

    it "parses 'a ?, b' in target list" do
      query = described_class.parse("SELECT a ?, b")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::A_Expr.new(
            kind: :AEXPR_OP,
            name: [PgQuery::Node.from_string('?')],
            lexpr: PgQuery::Node.from(
              PgQuery::ColumnRef.new(
                fields: [
                  PgQuery::Node.from_string('a')
                ],
                location: 7
              )
            ),
            location: 9
          )
        )
      )
    end

    it "parses 'a ? AND b' in where clause" do
      query = described_class.parse("SELECT * FROM x WHERE a ? AND b")
      expr = query.tree.stmts.first.stmt.select_stmt.where_clause
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::BoolExpr.new(
            boolop: :AND_EXPR,
            args: [
              PgQuery::Node.from(
                PgQuery::A_Expr.new(
                  kind: :AEXPR_OP,
                  name: [PgQuery::Node.from_string('?')],
                  lexpr: PgQuery::Node.from(
                    PgQuery::ColumnRef.new(
                      fields: [
                        PgQuery::Node.from_string('a')
                      ],
                      location: 22
                    )
                  ),
                  location: 24
                )
              ),
              PgQuery::Node.from(
                PgQuery::ColumnRef.new(
                  fields: [
                    PgQuery::Node.from_string('b')
                  ],
                  location: 30
                )
              )
            ],
            location: 26
          )
        )
      )
    end

    it "parses 'JOIN y ON a = ? JOIN z ON c = d'" do
      # JOIN can be both a keyword and a function, this test is to make sure we treat it as a keyword in this case
      q = described_class.parse("SELECT * FROM x JOIN y ON a = ? JOIN z ON c = d")
      expect(q.tree).not_to be_nil
    end

    it "parses 'a ? b' in where clause" do
      query = described_class.parse("SELECT * FROM x WHERE a ? b")
      expr = query.tree.stmts.first.stmt.select_stmt.where_clause
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::A_Expr.new(
            kind: :AEXPR_OP,
            name: [PgQuery::Node.from_string('?')],
            lexpr: PgQuery::Node.from(
              PgQuery::ColumnRef.new(
                fields: [
                  PgQuery::Node.from_string('a')
                ],
                location: 22
              )
            ),
            rexpr: PgQuery::Node.from(
              PgQuery::ColumnRef.new(
                fields: [
                  PgQuery::Node.from_string('b')
                ],
                location: 26
              )
            ),
            location: 24
          )
        )
      )
    end

    it "parses BETWEEN ? AND ?" do
      query = described_class.parse("SELECT x WHERE y BETWEEN ? AND ?")
      expect(query.tree).not_to be_nil
    end

    it "parses ?=?" do
      e = parse_expr("?=?")
      expect(e.name).to eq [PgQuery::Node.from_string('=')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?=x" do
      e = parse_expr("?=x")
      expect(e.name).to eq [PgQuery::Node.from_string('=')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.column_ref).not_to be_nil
    end

    it "parses x=?" do
      e = parse_expr("x=?")
      expect(e.name).to eq [PgQuery::Node.from_string('=')]
      expect(e.lexpr.column_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?!=?" do
      e = parse_expr("?!=?")
      expect(e.name).to eq [PgQuery::Node.from_string('<>')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?!=x" do
      e = parse_expr("?!=x")
      expect(e.name).to eq [PgQuery::Node.from_string('<>')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.column_ref).not_to be_nil
    end

    it "parses x!=?" do
      e = parse_expr("x!=?")
      expect(e.name).to eq [PgQuery::Node.from_string('<>')]
      expect(e.lexpr.column_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?-?" do
      e = parse_expr("?-?")
      expect(e.name).to eq [PgQuery::Node.from_string('-')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?<?-?" do
      e = parse_expr("?<?-?")
      expect(e.name).to eq [PgQuery::Node.from_string('<')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.a_expr).not_to be_nil
    end

    it "parses ?+?" do
      e = parse_expr("?+?")
      expect(e.name).to eq [PgQuery::Node.from_string('+')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?*?" do
      e = parse_expr("?*?")
      expect(e.name).to eq [PgQuery::Node.from_string('*')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    it "parses ?/?" do
      e = parse_expr("?/?")
      expect(e.name).to eq [PgQuery::Node.from_string('/')]
      expect(e.lexpr.param_ref).not_to be_nil
      expect(e.rexpr.param_ref).not_to be_nil
    end

    # http://www.postgresql.org/docs/devel/static/functions-json.html
    # http://www.postgresql.org/docs/devel/static/hstore.html
    it "parses hstore/JSON operators containing ?" do
      e = parse_expr("'{\"a\":1, \"b\":2}'::jsonb ? 'b'")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.a_const).not_to be_nil

      e = parse_expr("? ? ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil

      e = parse_expr("'{\"a\":1, \"b\":2, \"c\":3}'::jsonb ?| array['b', 'c']")
      expect(e.name).to eq [PgQuery::Node.from_string('?|')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.a_array_expr).not_to be_nil

      e = parse_expr("? ?| ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil

      e = parse_expr("'[\"a\", \"b\"]'::jsonb ?& array['a', 'b']")
      expect(e.name).to eq [PgQuery::Node.from_string('?&')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.a_array_expr).not_to be_nil

      e = parse_expr("? ?& ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil
    end

    # http://www.postgresql.org/docs/devel/static/functions-geometry.html
    it "parses geometric operators containing ?" do
      e = parse_expr("lseg '((-1,0),(1,0))' ?# box '((-2,-2),(2,2))'")
      expect(e.name).to eq [PgQuery::Node.from_string('?#')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("? ?# ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil

      e = parse_expr("?- lseg '((-1,0),(1,0))'")
      expect(e.name).to eq [PgQuery::Node.from_string('?-')]
      expect(e.lexpr).to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("?- ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?-')]
      expect(e.lexpr).to be_nil
      expect(e.rexpr.param_ref).not_to be_nil

      e = parse_expr("point '(1,0)' ?- point '(0,0)'")
      expect(e.name).to eq [PgQuery::Node.from_string('?-')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("? ?- ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil

      e = parse_expr("?| lseg '((-1,0),(1,0))'")
      expect(e.name).to eq [PgQuery::Node.from_string('?|')]
      expect(e.lexpr).to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("?| ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?|')]
      expect(e.lexpr).to be_nil
      expect(e.rexpr.param_ref).not_to be_nil

      e = parse_expr("point '(0,1)' ?| point '(0,0)'")
      expect(e.name).to eq [PgQuery::Node.from_string('?|')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("? ?| ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil

      e = parse_expr("lseg '((0,0),(0,1))' ?-| lseg '((0,0),(1,0))'")
      expect(e.name).to eq [PgQuery::Node.from_string('?-|')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("? ?-| ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.a_expr).not_to be_nil
      expect(e.rexpr).to be_nil

      e = parse_expr("lseg '((-1,0),(1,0))' ?|| lseg '((-1,2),(1,2))'")
      expect(e.name).to eq [PgQuery::Node.from_string('?||')]
      expect(e.lexpr.type_cast).not_to be_nil
      expect(e.rexpr.type_cast).not_to be_nil

      e = parse_expr("? ?|| ?")
      expect(e.name).to eq [PgQuery::Node.from_string('?')]
      expect(e.lexpr.node).to eq :a_expr
      expect(e.rexpr).to be_nil
    end

    it "parses substituted pseudo keywords in extract()" do
      query = described_class.parse("SELECT extract(? from NOW())")
      expr = query.tree.stmts.first.stmt.select_stmt.target_list[0].res_target.val
      expect(expr).to eq(
        PgQuery::Node.from(
          PgQuery::FuncCall.new(
            funcname: [PgQuery::Node.from_string('pg_catalog'), PgQuery::Node.from_string('date_part')],
            args: [
              PgQuery::Node.from(PgQuery::ParamRef.new(number: 0, location: 15)),
              PgQuery::Node.from(
                PgQuery::FuncCall.new(
                  funcname: [PgQuery::Node.from_string('now')],
                  location: 22
                )
              )
            ],
            location: 7
          )
        )
      )
    end

    it "parses $1?" do
      query = described_class.parse("SELECT 1 FROM x WHERE x IN ($1?, $1?)")
      expect(query.tree).not_to be_nil
    end

    it "parses SET x = ?" do
      query = described_class.parse("SET statement_timeout = ?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET x=?" do
      query = described_class.parse("SET statement_timeout=?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET TIME ZONE ?" do
      query = described_class.parse("SET TIME ZONE ?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET SCHEMA ?" do
      query = described_class.parse("SET SCHEMA ?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET ROLE ?" do
      query = described_class.parse("SET ROLE ?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET SESSION AUTHORIZATION ?" do
      query = described_class.parse("SET SESSION AUTHORIZATION ?")
      expect(query.tree).not_to be_nil
    end

    it "parses SET encoding = UTF?" do
      query = described_class.parse("SET encoding = UTF?")
      expect(query.tree).not_to be_nil
    end

    it "parses ?=ANY(..) constructs" do
      query = described_class.parse("SELECT 1 FROM x WHERE ?= ANY(z)")
      expect(query.tree).not_to be_nil
    end

    it "parses KEYWORD? constructs" do
      query = described_class.parse("select * from sessions where pid ilike? and id=? ")
      expect(query.tree).not_to be_nil
    end

    it "parses E?KEYWORD constructs" do
      query = described_class.parse("SELECT 1 FROM x WHERE nspname NOT LIKE E?AND nspname NOT LIKE ?")
      expect(query.tree).not_to be_nil
    end

    it "parses complicated queries" do
      query = described_class.parse("BEGIN;SET statement_timeout=?;COMMIT;SELECT DISTINCT ON (nspname, seqname) nspname, seqname, quote_ident(nspname) || ? || quote_ident(seqname) AS safename, typname FROM ( SELECT depnsp.nspname, dep.relname as seqname, typname FROM pg_depend JOIN pg_class on classid = pg_class.oid JOIN pg_class dep on dep.oid = objid JOIN pg_namespace depnsp on depnsp.oid= dep.relnamespace JOIN pg_class refclass on refclass.oid = refclassid JOIN pg_class ref on ref.oid = refobjid JOIN pg_namespace refnsp on refnsp.oid = ref.relnamespace JOIN pg_attribute refattr ON (refobjid, refobjsubid) = (refattr.attrelid, refattr.attnum) JOIN pg_type ON refattr.atttypid = pg_type.oid WHERE pg_class.relname = ? AND refclass.relname = ? AND dep.relkind in (?) AND ref.relkind in (?) AND typname IN (?) UNION ALL SELECT nspname, seq.relname, typname FROM pg_attrdef JOIN pg_attribute ON (attrelid, attnum) = (adrelid, adnum) JOIN pg_type on pg_type.oid = atttypid JOIN pg_class rel ON rel.oid = attrelid JOIN pg_class seq ON seq.relname = regexp_replace(adsrc, $re$^nextval\\(?::regclass\\)$$re$, $$\\?$$) AND seq.relnamespace = rel.relnamespace JOIN pg_namespace nsp ON nsp.oid = seq.relnamespace WHERE adsrc ~ ? AND seq.relkind = ? AND typname IN (?) UNION ALL SELECT nspname, relname, CAST(? AS TEXT) FROM pg_class JOIN pg_namespace nsp ON nsp.oid = relnamespace WHERE relkind = ? ) AS seqs ORDER BY nspname, seqname, typname")
      expect(query.tree).not_to be_nil
    end

    it "parses cast(? as varchar(2))" do
      query = described_class.parse("SELECT cast(? as varchar(2))")
      expect(query.tree).not_to be_nil
    end
  end
end
