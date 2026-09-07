--
-- PostgreSQL database dump
--

\restrict 8RfJ5sdB6OfDawO3Y3BMQdQkRra0SnxebLpUN0pJHSVOgXNmArgzPShB7rKcrfu

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: banking; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA banking;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: banking; Owner: -
--

CREATE TABLE banking.accounts (
    account_id bigint NOT NULL,
    customer_id bigint NOT NULL,
    account_number character varying(30) NOT NULL,
    account_type character varying(30) NOT NULL,
    balance numeric(15,2) DEFAULT 0,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: accounts_account_id_seq; Type: SEQUENCE; Schema: banking; Owner: -
--

CREATE SEQUENCE banking.accounts_account_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_account_id_seq; Type: SEQUENCE OWNED BY; Schema: banking; Owner: -
--

ALTER SEQUENCE banking.accounts_account_id_seq OWNED BY banking.accounts.account_id;


--
-- Name: audit_log; Type: TABLE; Schema: banking; Owner: -
--

CREATE TABLE banking.audit_log (
    audit_id bigint NOT NULL,
    username character varying(100),
    action character varying(100),
    object_name character varying(200),
    action_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: audit_log_audit_id_seq; Type: SEQUENCE; Schema: banking; Owner: -
--

CREATE SEQUENCE banking.audit_log_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: banking; Owner: -
--

ALTER SEQUENCE banking.audit_log_audit_id_seq OWNED BY banking.audit_log.audit_id;


--
-- Name: branches; Type: TABLE; Schema: banking; Owner: -
--

CREATE TABLE banking.branches (
    branch_id integer NOT NULL,
    branch_name character varying(100),
    city character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: branches_branch_id_seq; Type: SEQUENCE; Schema: banking; Owner: -
--

CREATE SEQUENCE banking.branches_branch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branches_branch_id_seq; Type: SEQUENCE OWNED BY; Schema: banking; Owner: -
--

ALTER SEQUENCE banking.branches_branch_id_seq OWNED BY banking.branches.branch_id;


--
-- Name: customers; Type: TABLE; Schema: banking; Owner: -
--

CREATE TABLE banking.customers (
    customer_id bigint NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    email character varying(200),
    phone character varying(30),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: customers_customer_id_seq; Type: SEQUENCE; Schema: banking; Owner: -
--

CREATE SEQUENCE banking.customers_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: banking; Owner: -
--

ALTER SEQUENCE banking.customers_customer_id_seq OWNED BY banking.customers.customer_id;


--
-- Name: transactions; Type: TABLE; Schema: banking; Owner: -
--

CREATE TABLE banking.transactions (
    transaction_id bigint NOT NULL,
    account_id bigint NOT NULL,
    transaction_type character varying(20) NOT NULL,
    amount numeric(15,2) NOT NULL,
    status character varying(20) DEFAULT 'SUCCESS'::character varying,
    transaction_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: transactions_transaction_id_seq; Type: SEQUENCE; Schema: banking; Owner: -
--

CREATE SEQUENCE banking.transactions_transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: banking; Owner: -
--

ALTER SEQUENCE banking.transactions_transaction_id_seq OWNED BY banking.transactions.transaction_id;


--
-- Name: accounts account_id; Type: DEFAULT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.accounts ALTER COLUMN account_id SET DEFAULT nextval('banking.accounts_account_id_seq'::regclass);


--
-- Name: audit_log audit_id; Type: DEFAULT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.audit_log ALTER COLUMN audit_id SET DEFAULT nextval('banking.audit_log_audit_id_seq'::regclass);


--
-- Name: branches branch_id; Type: DEFAULT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.branches ALTER COLUMN branch_id SET DEFAULT nextval('banking.branches_branch_id_seq'::regclass);


--
-- Name: customers customer_id; Type: DEFAULT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.customers ALTER COLUMN customer_id SET DEFAULT nextval('banking.customers_customer_id_seq'::regclass);


--
-- Name: transactions transaction_id; Type: DEFAULT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.transactions ALTER COLUMN transaction_id SET DEFAULT nextval('banking.transactions_transaction_id_seq'::regclass);


--
-- Name: accounts accounts_account_number_key; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.accounts
    ADD CONSTRAINT accounts_account_number_key UNIQUE (account_number);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (account_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (branch_id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: idx_transactions_account; Type: INDEX; Schema: banking; Owner: -
--

CREATE INDEX idx_transactions_account ON banking.transactions USING btree (account_id);


--
-- Name: accounts accounts_customer_id_fkey; Type: FK CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.accounts
    ADD CONSTRAINT accounts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES banking.customers(customer_id);


--
-- Name: transactions transactions_account_id_fkey; Type: FK CONSTRAINT; Schema: banking; Owner: -
--

ALTER TABLE ONLY banking.transactions
    ADD CONSTRAINT transactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES banking.accounts(account_id);


--
-- PostgreSQL database dump complete
--

\unrestrict 8RfJ5sdB6OfDawO3Y3BMQdQkRra0SnxebLpUN0pJHSVOgXNmArgzPShB7rKcrfu

