class Podbay::Components::Daemon
  RSpec.describe Iptables do
    let(:block) { double('iptables') }
    let(:iptables) { Iptables.new { |r| block.run(r) } }
    let(:iptables_retval) { true }

    def should_run(cmd)
      expect(block).to receive(:run).with(cmd).and_return(true).once
      subject
    end

    before do
      allow(block).to receive(:run).and_return(iptables_retval)
    end

    describe '#table' do
      subject { iptables.table(name) }

      context 'with name=filter' do
        let(:name) { 'filter' }
        it { is_expected.to have_attributes(name: 'filter') }
      end

      context 'with name=nat' do
        let(:name) { 'nat' }
        it { is_expected.to have_attributes(name: 'nat') }
      end
    end # #table

    describe '#chain' do
      subject { iptables.chain(name) }

      context 'with name=INPUT' do
        let(:name) { 'INPUT' }
        it { is_expected.to be_a Iptables::Chain }
        it { is_expected.to have_attributes(name: 'INPUT') }
      end
    end # #chain

    describe Iptables::Table do
      let(:table) { iptables.table(table_name) }

      describe '#chain' do
        subject { table.chain(name) }

        context 'with table_name="filter"' do
          let(:table_name) { 'filter' }

          context 'with name=INPUT' do
            let(:name) { 'INPUT' }
            it { is_expected.to be_a Iptables::Chain }
            it { is_expected.to have_attributes(name: 'INPUT') }
          end

          context 'with name=input' do
            let(:name) { 'input' }
            it { is_expected.to be_a Iptables::Chain }
            it { is_expected.to have_attributes(name: 'INPUT') }
          end

          context 'with name=FORWARD' do
            let(:name) { 'FORWARD' }
            it { is_expected.to be_a Iptables::Chain }
            it { is_expected.to have_attributes(name: 'FORWARD') }
          end
        end # with table_name="filter"
      end # #chain

      describe '#run' do
        subject { table.run(desc) }

        context 'with table_name="filter"' do
          let(:table_name) { 'filter' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter hello world') }
          end

          context 'with desc="-A INPUT -i lo -j ACCEPT"' do
            let(:desc) { '-A INPUT -i lo -j ACCEPT' }
            it { should_run('-t filter -A INPUT -i lo -j ACCEPT') }
          end
        end # with table_name="filter"

        context 'with table_name="nat"' do
          let(:table_name) { 'nat' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t nat hello world') }
          end

          context 'with desc="-A INPUT -i lo -j ACCEPT"' do
            let(:desc) { '-A INPUT -i lo -j ACCEPT' }
            it { should_run('-t nat -A INPUT -i lo -j ACCEPT') }
          end
        end # with table_name="nat"
      end # run
    end # Iptables::Table

    describe Iptables::Chain do
      let(:chain) { iptables.chain(chain_name) }
      let(:chain_name) { 'INPUT' }

      describe '#rule' do
        subject { chain.rule(desc) }

        context 'with desc="hello world"' do
          let(:desc) { 'hello world'.freeze }
          it { is_expected.to be_a Iptables::Rule }
          it { is_expected.to have_attributes(chain: chain, desc: desc) }
        end

        context 'with desc="-i lo -j ACCEPT"' do
          let(:desc) { '-i lo -j ACCEPT'.freeze }
          it { is_expected.to be_a Iptables::Rule }
          it { is_expected.to have_attributes(chain: chain, desc: desc) }
        end
      end # #rule

      describe '#append_rule' do
        subject { chain.append_rule(desc) }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -A INPUT hello world') }
          end

          context 'with desc="-i lo -j ACCEPT"' do
            let(:desc) { '-i lo -j ACCEPT' }
            it { should_run('-t filter -A INPUT -i lo -j ACCEPT') }
          end
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -A FORWARD hello world') }
          end

          context 'with desc="-i lo -j ACCEPT"' do
            let(:desc) { '-i lo -j ACCEPT' }
            it { should_run('-t filter -A FORWARD -i lo -j ACCEPT') }
          end
        end # with chain_name="FORWARD"
      end # #append_rule

      describe '#insert_rule' do
        subject { chain.insert_rule(desc, index) }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }

          context 'with index=nil' do
            let(:index) { nil }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I INPUT hello world') }
            end
          end # with index=nil

          context 'with index=1' do
            let(:index) { 1 }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I INPUT 1 hello world') }
            end
          end # with index=1

          context 'with index=10' do
            let(:index) { 10 }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I INPUT 10 hello world') }
            end
          end # with index=10
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }

          context 'with index=nil' do
            let(:index) { nil }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I FORWARD hello world') }
            end
          end # with index=nil

          context 'with index=1' do
            let(:index) { 1 }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I FORWARD 1 hello world') }
            end
          end # with index=1

          context 'with index=10' do
            let(:index) { 10 }

            context 'with desc="hello world"' do
              let(:desc) { 'hello world' }
              it { should_run('-t filter -I FORWARD 10 hello world') }
            end
          end # with index=10
        end # with chain_name="FORWARD"
      end # #insert_rule

      describe '#rule_exists?' do
        subject { chain.rule_exists?(desc) }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -C INPUT hello world') }
          end
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -C FORWARD hello world') }
          end
        end # with chain_name="FORWARD"
      end # #rule_exists?

      describe '#delete_rule' do
        subject { chain.delete_rule(desc) }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -D INPUT hello world') }
          end
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }
            it { should_run('-t filter -D FORWARD hello world') }
          end
        end # with chain_name="FORWARD"
      end # #delete_rule

      describe '#create' do
        subject { chain.create }

        context 'with chain_name="CUSTOM_CHAIN"' do
          let(:chain_name) { 'CUSTOM_CHAIN' }
          it { should_run('-t filter -N CUSTOM_CHAIN') }
        end # with chain_name="CUSTOM_CHAIN"

        context 'with iptables returning false' do
          let(:iptables_retval) { false }
          it {expect { subject }.to raise_error 'could not create chain INPUT'}
        end
      end # #create

      describe '#exists?' do
        subject { chain.exists? }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }
          it { should_run('-t filter -L INPUT -n') }
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }
          it { should_run('-t filter -L FORWARD -n') }
        end # with chain_name="FORWARD"
      end # #exists?

      describe '#flush' do
        subject { chain.flush }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }
          it { should_run('-t filter -F INPUT') }
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }
          it { should_run('-t filter -F FORWARD') }
        end # with chain_name="FORWARD"

        context 'with iptables returning false' do
          let(:iptables_retval) { false }
          it { expect { subject }.to raise_error 'could not flush chain INPUT' }
        end
      end # #flush

      describe '#delete' do
        subject { chain.delete }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }
          it { should_run('-t filter -X INPUT') }
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }
          it { should_run('-t filter -X FORWARD') }
        end # with chain_name="FORWARD"

        context 'with iptables returning false' do
          let(:iptables_retval) { false }
          it {expect { subject }.to raise_error 'could not delete chain INPUT'}
        end
      end # #delete

      describe '#policy' do
        subject { chain.policy(target) }

        context 'with chain_name="INPUT"' do
          let(:chain_name) { 'INPUT' }

          context 'with target="DROP"' do
            let(:target) { 'DROP' }
            it { should_run('-t filter -P INPUT DROP') }
          end
        end # with chain_name="INPUT"

        context 'with chain_name="FORWARD"' do
          let(:chain_name) { 'FORWARD' }

          context 'with target="ACCEPT"' do
            let(:target) { 'ACCEPT' }
            it { should_run('-t filter -P FORWARD ACCEPT') }
          end
        end # with chain_name="FORWARD"
      end # #policy
    end # Iptables::Chain

    describe Iptables::Rule do
      let(:chain) { iptables.chain('CHAIN_NAME') }
      let(:rule) { chain.rule(desc) }
      let(:chain_retval) { true }

      before do
        allow(chain).to receive(:append_rule).and_return(chain_retval)
        allow(chain).to receive(:insert_rule).and_return(chain_retval)
        allow(chain).to receive(:delete_rule).and_return(chain_retval)
      end

      describe '#append' do
        subject { rule.append }

        context 'with desc="hello world"' do
          let(:desc) { 'hello world' }

          it 'should call chain.append_rule' do
            expect(chain).to receive(:append_rule).with(desc).once
            subject
          end

          context 'with chain insert_rule returning false' do
            let(:chain_retval) { false }

            it 'should raise expected error' do
              expect { subject }.to raise_error 'could not append onto ' \
                'CHAIN_NAME: hello world'
            end
          end
        end
      end # #append

      describe '#insert' do
        subject { rule.insert(index) }

        context 'with index=nil' do
          let(:index) { nil }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }

            it 'should call chain.insert_rule' do
              expect(chain).to receive(:insert_rule).with(desc, nil)
                .and_return(true).once
              subject
            end

            context 'with chain insert_rule returning false' do
              let(:chain_retval) { false }

              it 'should raise expected error' do
                expect { subject }.to raise_error 'could not insert into ' \
                  'CHAIN_NAME: hello world'
              end
            end
          end
        end # with index=nil

        context 'with index=1' do
          let(:index) { 1 }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }

            it 'should call chain.insert_rule' do
              expect(chain).to receive(:insert_rule).with(desc, 1)
                .and_return(true).once
              subject
            end

            context 'with chain insert_rule returning false' do
              let(:chain_retval) { false }

              it 'should raise expected error' do
                expect { subject }.to raise_error 'could not insert into ' \
                  'CHAIN_NAME: hello world'
              end
            end
          end
        end # with index=1

        context 'with index=10' do
          let(:index) { 10 }

          context 'with desc="hello world"' do
            let(:desc) { 'hello world' }

            it 'should call chain.insert_rule' do
              expect(chain).to receive(:insert_rule).with(desc, 10)
                .and_return(true).once
              subject
            end

            context 'with chain insert_rule returning false' do
              let(:chain_retval) { false }

              it 'should raise expected error' do
                expect { subject }.to raise_error 'could not insert into ' \
                  'CHAIN_NAME: hello world'
              end
            end
          end
        end # with index=10
      end # #insert

      describe '#exists?' do
        subject { rule.exists? }

        context 'with desc="hello world"' do
          let(:desc) { 'hello world' }

          it 'should call chain.rule_exists?' do
            expect(chain).to receive(:rule_exists?).with(desc).once
            subject
          end
        end
      end # #exists?

      describe '#delete' do
        subject { rule.delete }

        context 'with desc="hello world"' do
          let(:desc) { 'hello world' }

          it 'should call chain.delete_rule' do
            expect(chain).to receive(:delete_rule).with(desc).once
            subject
          end

          context 'with chain insert_rule returning false' do
            let(:chain_retval) { false }

            it 'should raise expected error' do
              expect { subject }.to raise_error 'could not delete from ' \
                'CHAIN_NAME: hello world'
            end
          end
        end
      end # #delete
    end # Iptables::Rule
  end # Iptables
end # Podbay::Components::Daemon
