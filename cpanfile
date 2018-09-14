requires 'Any::Moose', '==0.26';
requires 'Config::General';
requires 'Const::Fast';
requires 'Contextual::Return';
requires 'Cwd';
requires 'Debuggit';
requires 'Exporter';
requires 'File::Basename';
requires 'File::HomeDir';
requires 'File::Spec';
requires 'IO::Prompter';
requires 'IPC::System::Simple';
requires 'List::MoreUtils';
requires 'List::Util';
requires 'Method::Signatures';
requires 'Method::Signatures::Modifiers';
requires 'Moose::Util::TypeConstraints';
requires 'MooseX::App::Cmd';
requires 'MooseX::App::Cmd::Command';
requires 'MooseX::Attribute::ENV';
requires 'MooseX::Declare';
requires 'MooseX::Has::Sugar';
requires 'MooseX::Types::Moose';
requires 'Path::Class';
requires 'Tie::IxHash';
requires 'TryCatch';
requires 'autodie';
requires 'base';
requires 'experimental';
requires 'local::lib';
requires 'perl', '5.014';
requires 'strict';
requires 'warnings';

on test => sub {
    requires 'Cwd';
    requires 'Data::Dumper';
    requires 'Data::Printer';
    requires 'Debuggit';
    requires 'Exporter';
    requires 'File::Basename';
    requires 'File::HomeDir';
    requires 'File::Temp';
    requires 'List::MoreUtils';
    requires 'Method::Signatures';
    requires 'Module::Runtime';
    requires 'Path::Class';
    requires 'Test::Most';
    requires 'Test::Trap';
    requires 'lib';
    requires 'parent';
};

